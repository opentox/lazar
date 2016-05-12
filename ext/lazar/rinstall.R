libdir = commandArgs(trailingOnly=TRUE)[1]
repo = "https://stat.ethz.ch/CRAN/"
#install.packages("Rserve",lib=libdir,repos=repo,dependencies=TRUE)
install.packages("iterators",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("foreach",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("gridExtra",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("ggplot2",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("pls",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("caret",lib=libdir,repos=repo,dependencies=TRUE);
install.packages("doMC",lib=libdir,repos=repo,dependencies=TRUE);
