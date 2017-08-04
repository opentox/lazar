#!/usr/bin/env ruby
require_relative '../lib/lazar.rb'
include OpenTox
newfile = ARGV[0].sub(/.csv/,"_mmol_log10.csv") 
p newfile
CSV.open(newfile, "wb") do |csv|
  CSV.read(ARGV[0]).each do |line|
    smi,mol = line
    if mol.numeric?
      c = Compound.from_smiles smi
      #delog = 10**(-1*mol.to_f) #if values already -log10 but mol
      mmol = mol.to_f*1000
      log = -Math.log10(mmol)
      csv << [smi, log]
    else
      csv << [smi, mol.gsub(/mol/,'mmol')]
    end
  end
end
