module OpenTox

  class Download

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
      name = endpoint+"-"+species
      table = [["SID","SMILES",name]]
      csv.each_slice(100) do |slice| # get SMILES in chunks
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
      File.open(File.join(File.dirname(__FILE__),"..","data",name+".csv"),"w+"){|f| f.puts table.collect{|row| row.join(",")}.join("\n")}
      meta = {
        :species => species,
        :endpoint => endpoint,
        :source => aid_url,
        :qmrf => qmrf,
        :warnings => warnings
      }
      File.open(File.join(File.dirname(__FILE__),"..","data",name+".json"),"w+"){|f| f.puts meta.to_json}
    end

  end

end
