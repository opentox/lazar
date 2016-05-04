#!/usr/bin/env ruby
require_relative '../lazar/lib/lazar'
include OpenTox
newfile = ARGV[0].sub(/.csv/,"_mmol.csv") 
p newfile
CSV.open(newfile, "wb") do |csv|
  CSV.read(ARGV[0]).each do |line|
    smi,mg = line
    if mg.numeric?
      c = Compound.from_smiles smi
      mmol = c.mg_to_mmol mg.to_f
      csv << [smi, mmol]
    else
      csv << [smi, mg.gsub(/mg/,'mmol')]
    end
  end
end
