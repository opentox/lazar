module OpenTox

  class Download

    DATA = File.join(File.dirname(__FILE__),"..","data")

    # Download classification dataset from PubChem into the data folder
    # @param [Integer] aid PubChem Assay ID
    # @param [String] active Name for the "Active" class
    # @param [String] inactive Name for the "Inactive" class
    # @param [String] species Species name
    # @param [String] endpoint Endpoint name
    # @param [Hash] qmrf Name and group for QMRF reports (optional)
    def self.pubchem_classification aid: , active: , inactive: , species: , endpoint:, qmrf: nil
      aid_url = File.join PUBCHEM_URI, "assay/aid/#{aid}"
      
      # Get assay data in chunks
      # Assay record retrieval is limited to 10000 SIDs
      # https://pubchemdocs.ncbi.nlm.nih.gov/pug-rest-tutorial$_Toc458584435
      list = JSON.parse(RestClientWrapper.get(File.join aid_url, "sids/JSON?list_return=listkey").to_s)["IdentifierList"]
      listkey = list["ListKey"]
      size = list["Size"]
      start = 0
      csv = []
      while start < size
        url = File.join aid_url, "CSV?sid=listkey&listkey=#{listkey}&listkey_start=#{start}&listkey_count=10000"
        csv += CSV.parse(RestClientWrapper.get(url).to_s).select{|r| r[0].match /^\d/} # discard header rows
        start += 10000
      end
      warnings = []
      name = endpoint.gsub(" ","_")+"-"+species.gsub(" ","_")
      $logger.debug name
      table = [["SID","SMILES",name]]
      csv.each_slice(100) do |slice| # get SMILES in chunks, size limit is 100
        cids = slice.collect{|s| s[2]}
        pubchem_cids = []
        JSON.parse(RestClientWrapper.get(File.join(PUBCHEM_URI,"compound/cid/#{cids.join(",")}/property/CanonicalSMILES/JSON")).to_s)["PropertyTable"]["Properties"].each do |prop|
          i = cids.index(prop["CID"].to_s)
          value = slice[i][3]
          if value == "Active"
            table << [slice[i][1].to_s,prop["CanonicalSMILES"],active]
            pubchem_cids << prop["CID"].to_s
          elsif value == "Inactive"
            table << [slice[i][1].to_s,prop["CanonicalSMILES"],inactive]
            pubchem_cids << prop["CID"].to_s
          else
            warnings << "Ignoring CID #{prop["CID"]}/ SMILES #{prop["CanonicalSMILES"]}, because PubChem activity is '#{value}'."
          end
        end
        (cids-pubchem_cids).each { |cid| warnings << "Could not retrieve SMILES for CID '#{cid}', all entries are ignored." }
      end
      File.open(File.join(DATA,name+".csv"),"w+"){|f| f.puts table.collect{|row| row.join(",")}.join("\n")}
      meta = {
        :species => species,
        :endpoint => endpoint,
        :source => "https://pubchem.ncbi.nlm.nih.gov/bioassay/#{aid}",
        :qmrf => qmrf,
        :warnings => warnings
      }
      File.open(File.join(DATA,name+".json"),"w+"){|f| f.puts meta.to_json}
      File.join(DATA,name+".csv")
    end

    # Download regression dataset from PubChem into the data folder
    # Uses -log10 transformed experimental data in mmol units
    # @param [String] aid PubChem Assay ID
    # @param [String] species Species name
    # @param [String] endpoint Endpoint name
    # @param [Hash] qmrf Name and group for QMRF reports (optional)
    def self.pubchem_regression aid: , species: , endpoint:, qmrf: nil
      aid_url = File.join PUBCHEM_URI, "assay/aid/#{aid}"
      
      # Get assay data in chunks
      # Assay record retrieval is limited to 10000 SIDs
      # https://pubchemdocs.ncbi.nlm.nih.gov/pug-rest-tutorial$_Toc458584435
      list = JSON.parse(RestClientWrapper.get(File.join aid_url, "sids/JSON?list_return=listkey").to_s)["IdentifierList"]
      listkey = list["ListKey"]
      size = list["Size"]
      start = 0
      csv = []
      unit = nil
      while start < size
        url = File.join aid_url, "CSV?sid=listkey&listkey=#{listkey}&listkey_start=#{start}&listkey_count=10000"
        # get unit
        unit ||= CSV.parse(RestClientWrapper.get(url).to_s).select{|r| r[0] == "RESULT_UNIT"}[0][8]
        csv += CSV.parse(RestClientWrapper.get(url).to_s).select{|r| r[0].match /^\d/} # discard header rows
        start += 10000
      end
      warnings = []
      name = endpoint.gsub(" ","_")+"-"+species.gsub(" ","_")
      $logger.debug name
      table = [["SID","SMILES","-log10(#{name} [#{unit}])"]]
      csv.each_slice(100) do |slice| # get SMILES in chunks, size limit is 100
        cids = slice.collect{|s| s[2]}
        pubchem_cids = []
        JSON.parse(RestClientWrapper.get(File.join(PUBCHEM_URI,"compound/cid/#{cids.join(",")}/property/CanonicalSMILES/JSON")).to_s)["PropertyTable"]["Properties"].each do |prop|
          i = cids.index(prop["CID"].to_s)
          value = slice[i][8]
          if value
            value = -Math.log10(value.to_f)
            table << [slice[i][1].to_s,prop["CanonicalSMILES"],value]
            pubchem_cids << prop["CID"].to_s
          else
            warnings << "Ignoring CID #{prop["CID"]}/ SMILES #{prop["CanonicalSMILES"]}, because PubChem activity is '#{value}'."
          end
        end
        (cids-pubchem_cids).each { |cid| warnings << "Could not retrieve SMILES for CID '#{cid}', all entries are ignored." }
      end
      File.open(File.join(DATA,name+".csv"),"w+"){|f| f.puts table.collect{|row| row.join(",")}.join("\n")}
      meta = {
        :species => species,
        :endpoint => endpoint,
        :source => "https://pubchem.ncbi.nlm.nih.gov/bioassay/#{aid}",
        :unit => unit,
        :qmrf => qmrf,
        :warnings => warnings
      }
      File.open(File.join(DATA,name+".json"),"w+"){|f| f.puts meta.to_json}
      File.join(DATA,name+".csv")
    end

    # Combine mutagenicity data from Kazius, Hansen and EFSA and download into the data folder
    def self.mutagenicity
      $logger.debug "Mutagenicity"
      # TODO add download/conversion programs to lazar dependencies
      hansen_url = "http://doc.ml.tu-berlin.de/toxbenchmark/Mutagenicity_N6512.csv"
      kazius_url = "http://cheminformatics.org/datasets/bursi/cas_4337.zip"
      efsa_url = "https://data.europa.eu/euodp/data/storage/f/2017-07-19T142131/GENOTOX data and dictionary.xls"
      
      parts = File.join(DATA, "parts")
      FileUtils.mkdir_p parts
      Dir[File.join(parts,"hansen.*")].each{|f| FileUtils.rm f }
      Dir[File.join(parts,"cas_4337.*")].each{|f| FileUtils.rm f }
      Dir[File.join(parts,"efsa.*")].each{|f| FileUtils.rm f }
      File.open(File.join(parts,"hansen-original.csv"),"w+"){|f| f.puts RestClientWrapper.get(hansen_url).to_s }

      # convert hansen
      hansen = CSV.read File.join(parts,"hansen-original.csv")
      hansen.shift

      map = {"0" => "non-mutagenic","1" => "mutagenic"}
      File.open(File.join(parts,"hansen.csv"),"w+") do |f|
        f.puts "ID,SMILES,Mutagenicity"
        hansen.each do |row|
          f.puts [row[0],row[5],map[row[2]]].join "," 
        end
      end
      File.open(File.join(parts,"cas_4337.zip"),"w+"){|f| f.puts RestClientWrapper.get(kazius_url).to_s }
      `cd #{parts} && unzip cas_4337.zip`
      `cd #{parts} && wget #{URI.escape efsa_url} -O efsa.xls`
      `cd #{parts} && xls2csv -s cp1252 -d utf-8 -x -c "	" efsa.xls > efsa.tsv`

      # convert EFSA data to mutagenicity classifications
      i = 0
      db = {}
      CSV.foreach(File.join(parts,"efsa.tsv"), :encoding => "UTF-8", :col_sep => "\t", :liberal_parsing => true) do |row|
        if i > 0 and row[11] and !row[11].empty? and row[24].match(/Salmonella/i) and ( row[25].match("TA 98") or row[25].match("TA 100") ) and row[33]
          begin
            c = OpenTox::Compound.from_smiles(row[11].gsub('"','')).smiles
          rescue
            c = OpenTox::Compound.from_inchi(row[12]).smiles # some smiles (row[11]) contain non-parseable characters
          end
          db[c] ||= {}
          db[c][:id] ||= row[2]
          if row[33].match(/Positiv/i)
            db[c][:value] = "mutagenic" # at least one positive result in TA 98 or TA 100
          elsif row[33].match(/Negativ/i)
            db[c][:value] ||= "non-mutagenic"
          end
        end
        i += 1
      end
      File.open(File.join(parts,"efsa.csv"),"w+") do |f|
        f.puts "ID,SMILES,Mutagenicity"
        db.each do |s,v|
          f.puts [v[:id],s,v[:value]].join ","
        end
      end

      # merge datasets
      hansen = Dataset.from_csv_file File.join(parts,"hansen.csv")
      efsa = Dataset.from_csv_file File.join(parts,"efsa.csv")
      kazius = Dataset.from_sdf_file File.join(parts,"cas_4337.sdf")
      datasets = [hansen,efsa,kazius]
      map = {"mutagen" => "mutagenic", "nonmutagen" => "non-mutagenic"}
      dataset = Dataset.merge datasets: datasets, features: datasets.collect{|d| d.bioactivity_features.first}, value_maps: [nil,nil,map], keep_original_features: false, remove_duplicates: true
      dataset.merged_features.first.name = "Mutagenicity"
      File.open(File.join(DATA,"Mutagenicity-Salmonella_typhimurium.csv"),"w+"){|f| f.puts dataset.to_csv}
      meta = {
        :species => "Salmonella typhimurium",
        :endpoint => "Mutagenicity",
        :source => [kazius_url,hansen_url,efsa_url].join(", "),
        :qmrf => { "group": "QMRF 4.10. Mutagenicity", "name": "OECD 471 Bacterial Reverse Mutation Test"},
      }
      File.open(File.join(DATA,"Mutagenicity-Salmonella_typhimurium.json"),"w+"){|f| f.puts meta.to_json}
      
      # cleanup
      datasets << dataset
      datasets.each{|d| d.delete }
      File.join(DATA,"Mutagenicity-Salmonella_typhimurium.csv")
    end

    # Download Blood Brain Barrier Penetration dataset into the data folder
    def self.blood_brain_barrier
      url =  "http://cheminformatics.org/datasets/li/bbp2.smi"
      name = "Blood_Brain_Barrier_Penetration-Human"
      $logger.debug name
      map = {"n" => "non-penetrating", "p" => "penetrating"}
      table = CSV.parse RestClientWrapper.get(url).to_s, :col_sep => "\t"
      File.open(File.join(DATA,name+".csv"),"w+") do |f|
        f.puts "ID,SMILES,#{name}"
        table.each do |row|
          f.puts [row[1],row[0],map[row[3]]].join(",")
        end
      end
      meta = {
        :species => "Human",
        :endpoint => "Blood Brain Barrier Penetration",
        :source => url,
        :qmrf => {"name": "QMRF 5.4. Toxicokinetics.Blood-brain barrier penetration", "group": "QMRF 5. Toxicokinetics"},
      }
      File.open(File.join(DATA,name+".json"),"w+"){|f| f.puts meta.to_json}
    end

    # Download the combined LOAEL dataset from Helma et al 2018 into the data folder
    def self.loael
      # TODO: fix url??
      url = "https://raw.githubusercontent.com/opentox/loael-paper/revision/data/training_log10.csv"
      name = "Lowest_observed_adverse_effect_level-Rats"
      $logger.debug name
      File.open(File.join(DATA,name+".csv"),"w+") do |f|
        CSV.parse(RestClientWrapper.get(url).to_s) do |row|
          f.puts [row[0],row[1]].join ","
        end
      end
      meta = {
        :species => "Rat",
        :endpoint => "Lowest observed adverse effect level",
        :source => url,
        :unit => "mmol/kg_bw/day",
        :qmrf => {
          "name": "QMRF 4.14. Repeated dose toxicity",
          "group": "QMRF 4.Human Health Effects"
        }
      }
      File.open(File.join(DATA,name+".json"),"w+"){|f| f.puts meta.to_json}
    end

    # Download Daphnia dataset from http://www.michem.unimib.it/download/data/acute-aquatic-toxicity-to-daphnia-magna/ into the public folder
    # The original file requires an email request, this is a temporary workaround
    def self.daphnia
      url = "https://raw.githubusercontent.com/opentox/lazar-public-data/master/regression/daphnia_magna_mmol_log10.csv"
      name = "Acute_toxicity-Daphnia_magna"
      $logger.debug name
      File.open(File.join(DATA,name+".csv"),"w+") do |f|
        f.puts RestClientWrapper.get(url).to_s
      end
      meta = { "species": "Daphnia magna",
        "endpoint": "Acute toxicity",
        "source": "http://www.michem.unimib.it/download/data/acute-aquatic-toxicity-to-daphnia-magna/",
        "unit": "mmol/L",
        "qmrf": {
          "group": "QMRF 3.1. Short-term toxicity to Daphnia (immobilisation)",
          "name": "EC C. 2. Daphnia sp Acute Immobilisation Test"
        }
      }
      File.open(File.join(DATA,name+".json"),"w+"){|f| f.puts meta.to_json}
    end

    # Download all public lazar datasets into the data folder
    def self.public_data

      # Classification
      [
        {
          :aid => 1205,
          :species => "Rodents",
          :endpoint => "Carcinogenicity",
          :qmrf => {:group => "QMRF 4.12. Carcinogenicity", :name => "OECD 451 Carcinogenicity Studies"}
        },{
          :aid => 1208,
          :species => "Rat",
          :endpoint => "Carcinogenicity",
          :qmrf => {:group => "QMRF 4.12. Carcinogenicity", :name => "OECD 451 Carcinogenicity Studies"}
        },{
          :aid => 1199,
          :species => "Mouse",
          :endpoint => "Carcinogenicity",
          :qmrf => {:group => "QMRF 4.12. Carcinogenicity", :name => "OECD 451 Carcinogenicity Studies"}
        }
      ].each do |assay|
        Download.pubchem_classification aid: assay[:aid], species: assay[:species], endpoint: assay[:endpoint], active: "carcinogen", inactive: "non-carcinogen", qmrf: assay[:qmrf]
      end
      Download.mutagenicity
      Download.blood_brain_barrier

      # Regression
      [
        {
          :aid => 1195,
          :species => "Human",
          :endpoint => "Maximum Recommended Daily Dose",
          :qmrf => {
            "group": "QMRF 4.14. Repeated dose toxicity",
            "name": "OECD 452 Chronic Toxicity Studies"
          },
        },{
          :aid => 1208,
          :species => "Rat (TD50)",
          :endpoint => "Carcinogenicity",
          :qmrf => {
            :group => "QMRF 4.12. Carcinogenicity",
            :name => "OECD 451 Carcinogenicity Studies"
          }
        },{
          :aid => 1199,
          :species => "Mouse (TD50)",
          :endpoint => "Carcinogenicity",
          :qmrf => {
            :group => "QMRF 4.12. Carcinogenicity",
            :name => "OECD 451 Carcinogenicity Studies"
          }
        },{
          :aid => 1188,
          :species => "Fathead minnow",
          :endpoint => "Acute toxicity",
          :qmrf => {
            "group": "QMRF 3.3. Acute toxicity to fish (lethality)",
            "name": "EC C. 1. Acute Toxicity for Fish"
          }
        }
      ].each do |assay|
        Download.pubchem_regression aid: assay[:aid], species: assay[:species], endpoint: assay[:endpoint], qmrf: assay[:qmrf]
      end
      
      Download.loael
      Download.daphnia

=begin
        # 1204  estrogen receptor
        # 1259408, # GENE-TOX
        # 1159563 HepG2 cytotoxicity assay
        # 588209 hepatotoxicity
        # 1259333 cytotoxicity
        # 1159569 HepG2 cytotoxicity counterscreen Measured in Cell-Based System Using Plate Reader - 2153-03_Inhibitor_Dose_DryPowder_Activity
        # 2122 HTS Counterscreen for Detection of Compound Cytotoxicity in MIN6 Cells
        # 116724 Acute toxicity determined after intravenal administration in mice
        # 1148549 Toxicity in po dosed mouse assessed as mortality after 7 days
=end
    end

  end
end
