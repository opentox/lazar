libdir = commandArgs(trailingOnly=TRUE)[1]
repo = "https://stat.ethz.ch/CRAN/"
#install.packages("Rserve",lib=libdir,repos=repo,dependencies=TRUE)
install.packages("iterators",lib=libdir,repos=repo);
install.packages("foreach",lib=libdir,repos=repo);
install.packages("gridExtra",lib=libdir,repos=repo);
install.packages("ggplot2",lib=libdir,repos=repo);
install.packages("pls",lib=libdir,repos=repo);
install.packages("caret",lib=libdir,repos=repo);
install.packages("doMC",lib=libdir,repos=repo);
