libdir = commandArgs(trailingOnly=TRUE)[1]
#install.packages("Rserve",lib=libdir,configure.args=args)
repo = "https://stat.ethz.ch/CRAN/"
install.packages("gridExtra",lib=libdir,repos=repo);
install.packages("ggplot2",lib=libdir,repos=repo);
install.packages("pls",lib=libdir,repos=repo);
install.packages("caret",lib=libdir,repos=repo);
install.packages("doMC",lib=libdir,repos=repo);
