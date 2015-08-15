require 'fileutils'
main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))

# install OpenBabel

require 'mkmf'
require 'rbconfig'
require 'openbabel/version'

openbabel_version = 2.3.2

openbabel_dir = File.join main_dir, "openbabel"
src_dir = File.join openbabel_dir, "openbabel-#{openbabel_version}"
build_dir = File.join openbabel_dir, "build"
install_dir = openbabel_dir 
install_lib_dir = File.join install_dir, "lib"
lib_dir = File.join openbabel_dir, "lib", "openbabel"
ruby_src_dir = File.join src_dir, "scripts", "ruby"

begin
  nr_processors = `grep processor /proc/cpuinfo | wc -l` # speed up compilation, Linux only
rescue
  nr_processors = 1
end

Dir.chdir openbabel_dir do
  FileUtils.rm_rf src_dir
  puts "Downloading OpenBabel sources"
  system "curl -L -d use_mirror=netcologne 'http://downloads.sourceforge.net/project/openbabel/openbabel/#{ob_num_ver}/openbabel-#{ob_num_ver}.tar.gz' | tar xz"
  system "sed -i -e 's/-Wl,-flat_namespace//;s/-flat_namespace//' #{File.join ruby_src_dir, "extconf.rb"}" # remove unrecognized compiler option
  system "sed -i -e 's/Init_OpenBabel/Init_openbabel/g' #{File.join ruby_src_dir,"*cpp"}" # fix swig bindings
  system "sed  -i -e 's/Config::CONFIG/RbConfig::CONFIG/' #{File.join src_dir, "scripts", "CMakeLists.txt" }" # fix Ruby Config
  system "sed  -i -e 's/Config::CONFIG/RbConfig::CONFIG/' #{File.join ruby_src_dir, "extconf.rb" }" # fix Ruby Config
end
FileUtils.mkdir_p build_dir
FileUtils.mkdir_p install_dir
Dir.chdir build_dir do
  puts "Configuring OpenBabel"
  cmake = "cmake #{src_dir} -DCMAKE_INSTALL_PREFIX=#{install_dir} -DBUILD_GUI=OFF -DENABLE_TESTS=OFF -DRUBY_BINDINGS=ON"
  # set rpath for local installations
  # http://www.cmake.org/Wiki/CMake_RPATH_handling
  # http://vtk.1045678.n5.nabble.com/How-to-force-cmake-not-to-remove-install-rpath-td5721193.html
  cmake += " -DCMAKE_INSTALL_RPATH:STRING=\"#{install_lib_dir}\"" 
  system cmake
end

# local installation in gem directory
Dir.chdir build_dir do
  puts "Compiling OpenBabel sources."
  system "make -j#{nr_processors}"
  system "make install"
  ENV["PKG_CONFIG_PATH"] = File.dirname(File.expand_path(Dir["#{install_dir}/**/openbabel*pc"].first))
end

# get include and lib from pkg-config
ob_include=`pkg-config openbabel-2.0 --cflags-only-I`.sub(/\s+/,'').sub(/-I/,'')
ob_lib=`pkg-config openbabel-2.0 --libs-only-L`.sub(/\s+/,'').sub(/-L/,'')

# compile ruby bindings
puts "Compiling and installing OpenBabel Ruby bindings."
Dir.chdir ruby_src_dir do
  # fix rpath
  system "sed -i 's|with_ldflags.*$|with_ldflags(\"#\$LDFLAGS -dynamic -Wl,-rpath,#{install_lib_dir}\") do|' #{File.join(ruby_src_dir,'extconf.rb')}"
  system "#{RbConfig.ruby} extconf.rb --with-openbabel-include=#{ob_include} --with-openbabel-lib=#{ob_lib}"
  system "make -j#{nr_processors}"
end
FileUtils.cp(ruby_src_dir+"/openbabel.#{RbConfig::CONFIG["DLEXT"]}", "./")
FileUtils.mkdir_p lib_dir
FileUtils.mv "openbabel.#{RbConfig::CONFIG["DLEXT"]}" lib_dir
FileUtils.remove_entry_secure src_dir, build_dir

# install fminer
fminer_dir = File.join main_dir, "libfminer"
system "git clone git://github.com/amaunz/fminer2.git #{fminer_dir}"

["libbbrc","liblast"].each do |lib|
  FileUtils.cd File.join(fminer_dir,lib)
  system "sed -i 's,^INCLUDE_OB.*,INCLUDE_OB\ =\ #{ob_include},g' Makefile" 
  system "sed -i 's,^LDFLAGS_OB.*,LDFLAGS_OB\ =\ #{ob_lib},g' Makefile"
  system "sed -i 's,^INCLUDE_RB.*,INCLUDE_RB\ =\ #{RbConfig::CONFIG['rubyhdrdir']},g' Makefile" 
  system "make ruby"
end

# install last-utils
FileUtils.cd main_dir
"git clone git://github.com/amaunz/last-utils.git"

# install R packagemain_dir
