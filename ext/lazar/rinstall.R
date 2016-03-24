libdir = commandArgs(trailingOnly=TRUE)[1]
# chooseCRANmirror(ind=19); does not have any impact on selected server
#args=paste0("--prefix=",libdir,"/..")
#install.packages("Rserve",lib=libdir,configure.args=args)
install.packages("gridExtra",lib=libdir);
install.packages("ggplot2",lib=libdir);
install.packages("pls",lib=libdir);
install.packages("caret",lib=libdir);
install.packages("doMC",lib=libdir);
