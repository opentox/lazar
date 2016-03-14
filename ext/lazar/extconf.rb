require 'fileutils'
require 'rbconfig'

main_dir = File.expand_path(File.join(File.dirname(__FILE__),"..",".."))

# install OpenBabel


openbabel_version = "2.3.2"

openbabel_dir = File.join main_dir, "openbabel"
src_dir = openbabel_dir #File.join openbabel_dir, "openbabel-#{openbabel_version}"
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

# compile ruby bindings
=begin
puts "Compiling and installing OpenBabel Ruby bindings."
Dir.chdir ruby_src_dir do
  # fix rpath
  system "sed -i 's|with_ldflags.*$|with_ldflags(\"#\$LDFLAGS -dynamic -Wl,-rpath,#{install_lib_dir}\") do|' #{File.join(ruby_src_dir,'extconf.rb')}"
  system "#{RbConfig.ruby} extconf.rb --with-openbabel-include=#{ob_include} --with-openbabel-lib=#{ob_lib}"
  system "make -j#{nr_processors}"
end
=end

# install fminer
fminer_dir = File.join main_dir, "libfminer"
system "git clone git://github.com/amaunz/fminer2.git #{fminer_dir}"

["libbbrc","liblast"].each do |lib|
  FileUtils.cd File.join(fminer_dir,lib)
  system "sed -i 's,^INCLUDE_OB.*,INCLUDE_OB\ =\ #{ob_include},g' Makefile" 
  system "sed -i 's,^LDFLAGS_OB.*,LDFLAGS_OB\ =\ #{ob_lib},g' Makefile"
  system "sed -i 's,^INCLUDE_RB.*,INCLUDE_RB\ =\ #{RbConfig::CONFIG['rubyhdrdir']},g' Makefile" 
  # TODO fix in fminer Makefile
  system "sed -i 's,-g, -g -I #{RbConfig::CONFIG['rubyhdrdir']} -I #{RbConfig::CONFIG['rubyarchhdrdir']} -I,' Makefile" # fix include path (CH)
  system "sed -i '74s/$(CC)/$(CC) -Wl,-rpath,#{ob_lib.gsub('/','\/')} -L/' Makefile" # fix library path (CH)
  system "make ruby"
end

# install last-utils
FileUtils.cd main_dir
system "git clone git://github.com/amaunz/last-utils.git"
FileUtils.cd File.join(main_dir,"last-utils")
`sed -i '8s/"openbabel", //' lu.rb`

# install R packagemain_dir
$makefile_created = true
