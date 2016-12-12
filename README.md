lazar
=====

Ruby libraries for the lazar framework

Dependencies
------------

  lazar depends on a couple of external programs and libraries. All required libraries will be installed with the `gem install lazar` command. 
  If any of the dependencies fails to install, please check if all required development packages are installed from your operating systems package manager (e.g. `apt`, `rpm`, `pacman`, ...). 
  You will need a working Java runtime to use descriptor calculation algorithms from CDK and JOELib libraries.

Installation
------------

  `gem install lazar`

  Please be patient, the compilation of external libraries can be very time consuming. If installation fails you can try to install manually:

  ```
  git clone https://github.com/opentox/lazar.git
  cd lazar
  ruby ext/lazar/extconf.rb
  bundle install
  ```

  The output should give you more verbose information that can help in debugging (e.g. to identify missing libraries).

Documentation
-------------
* [API documentation](http://rdoc.info/gems/lazar)

Copyright
---------
Copyright (c) 2009-2016 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
