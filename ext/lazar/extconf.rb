require 'fileutils'
require 'rbconfig'

main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))

# install OpenBabel

openbabel_version = "2.3.2"

openbabel_dir = File.join main_dir, "openbabel"
src_dir = openbabel_dir 
build_dir = File.join src_dir, "build"
install_dir = openbabel_dir 
install_lib_dir = File.join install_dir, "lib"
lib_dir = File.join openbabel_dir, "lib", "openbabel"
ruby_src_dir = File.join src_dir, "scripts", "ruby"

begin
  nr_processors = `getconf _NPROCESSORS_ONLN`.to_i # should be POSIX compatible
rescue
  nr_processors = 1
end

FileUtils.mkdir_p openbabel_dir
Dir.chdir main_dir do
  FileUtils.rm_rf src_dir
  puts "Downloading OpenBabel sources"
  system "git clone https://github.com/openbabel/openbabel.git"
end

FileUtils.mkdir_p build_dir
FileUtils.mkdir_p install_dir
Dir.chdir build_dir do
  puts "Configuring OpenBabel"
  cmake = "cmake #{src_dir} -DCMAKE_INSTALL_PREFIX=#{install_dir} -DBUILD_GUI=OFF -DENABLE_TESTS=OFF -DRUN_SWIG=ON -DRUBY_BINDINGS=ON"
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

ob_include= File.expand_path File.join(File.dirname(__FILE__),"../../openbabel/include/openbabel-2.0")
ob_lib= File.expand_path File.join(File.dirname(__FILE__),"../../openbabel/lib")

$makefile_created = true
