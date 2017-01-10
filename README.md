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

Tutorial
--------

Execute the following commands either from an interactive Ruby shell or a Ruby script:

### Create and use `lazar` models for small molecules

#### Create a training dataset

  Create a CSV file with two columns. The first line should contain either SMILES or InChI (first column) and the endpoint (second column). The first column should contain either the SMILES or InChI of the training compounds, the second column the training compounds toxic activities (qualitative or quantitative). Use -log10 transformed values for regression datasets. Add metadata to a JSON file with the same basename containing the fields "species", "endpoint", "source" and "unit" (regression only). You can find example training data at [Github](https://github.com/opentox/lazar-public-data).

#### Create and validate a `lazar` model with default algorithms and parameters

  `validated_model = Model::Validation.create_from_csv_file EPAFHM_log10.csv`

#### Inspect crossvalidation results

  `validated_model.crossvalidations`

#### Predict a new compound

  Create a compound

  `compound = Compound.from_smiles "NC(=O)OCCC"`

  Predict Fathead Minnow Acute Toxicity

  `validated_model.predict compound`

#### Experiment with other algorithms

  You can pass algorithms parameters to the `Model::Validation.create_from_csv_file` command. The [API documentation](http://rdoc.info/gems/lazar) provides detailed instructions.

### Create and use `lazar` nanoparticle models

#### Create and validate a `nano-lazar` model from eNanoMapper with default algorithms and parameters

  `validated_model = Model::Validation.create_from_enanomapper`

  This command will mirror the eNanoMapper database in the local database, create a `nano-lazar` model and validate it with five independent 10-fold crossvalidations.

#### Inspect crossvalidation results

  `validated_model.crossvalidations`

#### Predict nanoparticle toxicities

  Choose a random nanoparticle from the "Potein Corona" dataset
  ```
  training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
  nanoparticle = training_dataset.substances.shuffle.first
  ```

  Predict the "Net Cell Association" endpoint

  `validated_model.predict nanoparticle`

#### Experiment with other datasets, endpoints and algorithms

  You can pass training_dataset, prediction_feature and algorithms parameters to the `Model::Validation.create_from_enanomapper` command. The [API documentation](http://rdoc.info/gems/lazar) provides detailed instructions.

Documentation
-------------
* [API documentation](http://rdoc.info/gems/lazar)

Copyright
---------
Copyright (c) 2009-2017 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
