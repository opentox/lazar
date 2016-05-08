#!/usr/bin/env ruby
require_relative '../lib/lazar'
include OpenTox
newfile = ARGV[0].sub(/.csv/,"_log10.csv") 
p newfile
i = 1
CSV.open(newfile, "wb") do |csv|
  CSV.read(ARGV[0]).each do |line|
    smi,mmol = line
    if mmol.numeric?
      c = Compound.from_smiles smi
      mmol = -Math.log10(mmol.to_f)
      csv << [smi, mmol]
    else
      #csv << [smi, "-log10(#{mmol})"]
      p "Line #{i}: '#{mmol}' is not a numeric value."
      csv << [smi, ""]
    end
    i += 1
  end
end
