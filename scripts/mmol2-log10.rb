#!/usr/bin/env ruby
require_relative '../lib/lazar'
include OpenTox

newfile = ARGV[0].sub(/.csv/,"_log10.csv")
p newfile
CSV.open(newfile, "wb") do |csv|
  i = 1
  CSV.read(ARGV[0]).each do |line|
    type,mmol = line
    if i == 1
      @type = type
      csv << ["SMILES", "-log10(#{mmol})"]
    else
      if mmol.numeric?
        if @type =~ /smiles/i
          c = Compound.from_smiles type
        elsif @type =~ /inchi/i
          c = Compound.from_inchi type
          type = c.smiles
        else
          p "Unknown type '#{type}' at line 1."
        end
        mmol = -Math.log10(mmol.to_f)
        csv << [type, mmol]
      else
        p "Line #{i}: '#{mmol}' is not a numeric value."
      end
    end
    i += 1
  end
end
