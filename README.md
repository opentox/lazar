lazar
=====

Ruby libraries for the lazar framework

Dependencies
------------

  lazar depends on a couple of external programs and libraries. On Debian 7 "Wheezy" systems you can install them with

   `sudo apt-get install build-essential ruby ruby-dev git cmake swig r-base r-base-dev openjdk-7-jre libgsl0-dev libxml2-dev zlib1g-dev libcairo2-dev`
  
  You will also need at least mongodb version 3.0, but Debian "Wheezy" provides version 2.4. Please follow the instructions at http://docs.mongodb.org/manual/tutorial/install-mongodb-on-debian/:

  ```
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10
  echo "deb http://repo.mongodb.org/apt/debian wheezy/mongodb-org/3.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.0.list
  sudo apt-get update
  sudo apt-get install -y mongodb-org
  ```

Installation
------------

  `gem install lazar`

  Please be patient, the compilation of OpenBabel and Fminer libraries can be very time consuming. If installation fails you can try to install manually:

  ```
  git clone https://github.com/opentox/lazar.git
  cd lazar
  ruby ext/lazar/extconf.rb
  sudo Rscript ext/lazar/rinstall.R
  bundle install
  ```

  The output should give you more verbose information that can help in debugging (e.g. to identify missing libraries).

Documentation
-------------
* [API documentation](http://rdoc.info/gems/lazar)

Copyright
---------
Copyright (c) 2009-2015 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
