module OpenTox
  module Algorithm
    class Fminer
      TABLE_OF_ELEMENTS = [
"H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca", "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd", "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg", "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm", "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Uut", "Fl", "Uup", "Lv", "Uus", "Uuo"]
        
      #
      # Run bbrc algorithm on dataset
      #
      # @param [OpenTox::Dataset] training dataset
      # @param [optional] parameters BBRC parameters, accepted parameters are
      #   - min_frequency  Minimum frequency (default 5)
      #   - feature_type Feature type, can be 'paths' or 'trees' (default "trees")
      #   - backbone BBRC classes, pass 'false' to switch off mining for BBRC representatives. (default "true")
      #   - min_chisq_significance Significance threshold (between 0 and 1)
      #   - nr_hits Set to "true" to get hit count instead of presence
      #   - get_target Set to "true" to obtain target variable as feature
      # @return [OpenTox::Dataset] Fminer Dataset
      def self.bbrc training_dataset, params={}

        time = Time.now
        bad_request_error "More than one prediction feature found in training_dataset #{training_dataset.id}" unless training_dataset.features.size == 1

        prediction_feature = training_dataset.features.first
        if params[:min_frequency]
          minfreq = params[:min_frequency]
        else
          per_mil = 5 # value from latest version
          i = training_dataset.feature_ids.index prediction_feature.id
          nr_labeled_cmpds = training_dataset.data_entries.select{|de| !de[i].nil?}.size
          minfreq = per_mil * nr_labeled_cmpds.to_f / 1000.0 # AM sugg. 8-10 per mil for BBRC, 50 per mil for LAST
          minfreq = 2 unless minfreq > 2
          minfreq = minfreq.round
        end

        @bbrc ||= Bbrc::Bbrc.new
        @bbrc.Reset
        if prediction_feature.numeric 
          @bbrc.SetRegression(true) # AM: DO NOT MOVE DOWN! Must happen before the other Set... operations!
        else
          bad_request_error "No accept values for "\
                            "dataset '#{training_dataset.id}' and "\
                            "feature '#{prediction_feature.id}'" unless prediction_feature.accept_values
          value2act = Hash[[*prediction_feature.accept_values.map.with_index]]
        end
        @bbrc.SetMinfreq(minfreq)
        @bbrc.SetType(1) if params[:feature_type] == "paths"
        @bbrc.SetBackbone(false) if params[:backbone] == "false"
        @bbrc.SetChisqSig(params[:min_chisq_significance].to_f) if params[:min_chisq_significance]
        @bbrc.SetConsoleOut(false)

        params[:nr_hits] ? nr_hits = params[:nr_hits] : nr_hits = false
        feature_dataset = FminerDataset.new(
            :training_dataset_id => training_dataset.id,
            :training_algorithm => "#{self.to_s}.bbrc",
            :training_feature_id => prediction_feature.id ,
            :training_parameters => {
              :min_frequency => minfreq,
              :nr_hits => nr_hits,
              :backbone => (params[:backbone] == false ? false : true) 
            }

        )
        feature_dataset.compounds = training_dataset.compounds

        # add data 
        training_dataset.compounds.each_with_index do |compound,i|
          @bbrc.AddCompound(compound.smiles,i+1)
          act = value2act[training_dataset.data_entries[i].first]
          @bbrc.AddActivity(act,i+1)
        end
        #g_median=@fminer.all_activities.values.to_scale.median

        #task.progress 10
        #step_width = 80 / @bbrc.GetNoRootNodes().to_f

        $logger.debug "BBRC setup: #{Time.now-time}"
        time = Time.now
        ftime = 0
        itime = 0
        rtime = 0
  
        # run @bbrc
        (0 .. @bbrc.GetNoRootNodes()-1).each do |j|
          results = @bbrc.MineRoot(j)
          results.each do |result|
            rt = Time.now
            f = YAML.load(result)[0]
            smarts = f.shift
            # convert fminer SMARTS representation into a more human readable format
            smarts.gsub!(%r{\[#(\d+)&(\w)\]}) do
             element = TABLE_OF_ELEMENTS[$1.to_i-1]
             $2 == "a" ? element.downcase : element
            end
            p_value = f.shift
            f.flatten!
  
=begin
            if (!@bbrc.GetRegression)
              id_arrs = f[2..-1].flatten
              max = OpenTox::Algorithm::Fminer.effect(f[2..-1].reverse, @fminer.db_class_sizes) # f needs reversal for bbrc
              effect = max+1
            else #regression part
              id_arrs = f[2]
              # DV: effect calculation
              f_arr=Array.new
              f[2].each do |id|
                id=id.keys[0] # extract id from hit count hash
                f_arr.push(@fminer.all_activities[id])
              end
              f_median=f_arr.to_scale.median
              if g_median >= f_median
                effect = 'activating'
              else
                effect = 'deactivating'
              end
            end
=end
            rtime += Time.now - rt
  
            ft = Time.now
            feature = OpenTox::FminerSmarts.find_or_create_by({
              "smarts" => smarts,
              "p_value" => p_value.to_f.abs.round(5),
              #"effect" => effect,
              "dataset_id" => feature_dataset.id
            })
            feature_dataset.feature_ids << feature.id
            ftime += Time.now - ft

            it = Time.now
            f.each do |id_count_hash|
              id_count_hash.each do |id,count|
                nr_hits ? count = count.to_i : count = 1
                feature_dataset.data_entries[id-1] ||= []
                feature_dataset.data_entries[id-1][feature_dataset.feature_ids.size-1] = count
              end
            end
            itime += Time.now - it
  
          end
        end

        $logger.debug "Fminer: #{Time.now-time} (read: #{rtime}, iterate: #{itime}, find/create Features: #{ftime})"
        time = Time.now

        feature_dataset.fill_nil_with 0

        $logger.debug "Prepare save: #{Time.now-time}"
        time = Time.now
        feature_dataset.save_all

        $logger.debug "Save: #{Time.now-time}"
        feature_dataset
  
      end
    end
  end
end
