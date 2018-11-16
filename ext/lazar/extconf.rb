require 'fileutils'
require 'rbconfig'
require 'mkmf'

main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))

# check for required programs
programs = ["R","Rscript","mongod","java","getconf","wget","unzip","xls2csv","xlsx2csv"]
programs.each do |program|
  abort "Please install #{program} on your system." unless find_executable program
end

abort "Please install Rserve on your system. Execute 'install.packages('Rserve')' in a R console running as root ('sudo R')."  unless `R CMD Rserve --version`.match(/^Rserve/)

# install R packages
r_dir = File.join main_dir, "R"
FileUtils.mkdir_p r_dir
#FileUtils.mkdir_p File.join(main_dir,"bin") # for Rserve binary
rinstall = File.expand_path(File.join(File.dirname(__FILE__),"rinstall.R"))
puts `Rscript --vanilla #{rinstall} #{r_dir}`

r_libs = Dir[File.join(r_dir,"*")].collect{|l| l.sub(r_dir, '').sub('/','')}.sort
["caret","doMC","foreach","ggplot2","gridExtra","iterators","pls"].each do |lib|
  abort "Failed to install R package '#{lib}'." unless r_libs.include?(lib)
end

# create a fake Makefile
File.open(File.join(File.dirname(__FILE__),"Makefile"),"w+") do |makefile|
  makefile.puts "all:\n\ttrue\n\ninstall:\n\ttrue\n"
end

$makefile_created = true
