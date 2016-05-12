#!/usr/bin/env ruby
require_relative '../lib/lazar'
include OpenTox
newfile = ARGV[0].sub(/.csv/,"_log10.csv") 
p newfile
CSV.open(newfile, "wb") do |csv|
  i = 1
  CSV.read(ARGV[0]).each do |line|
    smi,mmol = line
    if i == 1
      csv << [smi, "-log10(#{mmol})"]
    else
      if mmol.numeric?
        c = Compound.from_smiles smi
        mmol = -Math.log10(mmol.to_f)
        csv << [smi, mmol]
      else
        p "Line #{i}: '#{mmol}' is not a numeric value."
        #csv << [smi, ""]
      end
    end
    i += 1
  end
end
