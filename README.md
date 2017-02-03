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

  This command will create a `lazar` model and validate it with three independent 10-fold crossvalidations.

#### Inspect crossvalidation results

  `validated_model.crossvalidations`

#### Predict a new compound

  Create a compound

  `compound = Compound.from_smiles "NC(=O)OCCC"`

  Predict Fathead Minnow Acute Toxicity

  `validated_model.predict compound`

#### Experiment with other algorithms

  You can pass algorithm specifications as parameters to the `Model::Validation.create_from_csv_file` and `Model::Lazar.create` commands. Algorithms for descriptors, similarity calculations, feature_selection and local models are specified in the `algorithm` parameter. Unspecified algorithms and parameters are substituted by default values. The example below selects 

  - MP2D fingerprint descriptors
  - Tanimoto similarity with a threshold of 0.1
  - no feature selection
  - weighted majority vote predictions

  ```
algorithms = {
  :descriptors => { # descriptor algorithm
    :method => "fingerprint", # fingerprint descriptors
    :type => "MP2D" # fingerprint type, e.g. FP4, MACCS
  },
  :similarity => { # similarity algorithm
    :method => "Algorithm::Similarity.tanimoto",
    :min => 0.1 # similarity threshold for neighbors
  },
  :feature_selection => nil, # no feature selection
  :prediction => { # local modelling algorithm
    :method => "Algorithm::Classification.weighted_majority_vote",
  },
}

training_dataset = Dataset.from_csv_file "hamster_carcinogenicity.csv"
model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
  ```

  The next example creates a regression model with

  - calculated descriptors from OpenBabel libraries
  - weighted cosine similarity and a threshold of 0.5
  - descriptors that are correlated with the endpoint
  - local partial least squares models from the R caret package

  ```
algorithms = {
  :descriptors => { # descriptor algorithm
    :method => "calculate_properties",
    :features => PhysChem.openbabel_descriptors,
  },
  :similarity => { # similarity algorithm
    :method => "Algorithm::Similarity.weighted_cosine",
    :min => 0.5
  },
  :feature_selection => { # feature selection algorithm
    :method => "Algorithm::FeatureSelection.correlation_filter",
  },
  :prediction => { # local modelling algorithm
    :method => "Algorithm::Caret.pls",
  },
}
training_dataset = Dataset.from_csv_file "EPAFHM_log10.csv"
model = Model::Lazar.create(training_dataset:training_dataset, algorithms:algorithms)
    ```

Please consult the [API documentation](http://rdoc.info/gems/lazar) and [source code](https:://github.com/opentox/lazar) for up to date information about implemented algorithms:

- Descriptor algorithms
  - [Compounds](http://www.rubydoc.info/gems/lazar/OpenTox/Compound)
  - [Nanoparticles](http://www.rubydoc.info/gems/lazar/OpenTox/Nanoparticle)
- [Similarity algorithms](http://www.rubydoc.info/gems/lazar/OpenTox/Algorithm/Similarity)
- [Feature selection algorithms](http://www.rubydoc.info/gems/lazar/OpenTox/Algorithm/FeatureSelection)
- Local models
  - [Classification](http://www.rubydoc.info/gems/lazar/OpenTox/Algorithm/Classification)
  - [Regression](http://www.rubydoc.info/gems/lazar/OpenTox/Algorithm/Regression)
  - [R caret](http://www.rubydoc.info/gems/lazar/OpenTox/Algorithm/Caret)


You can find more working examples in the `lazar` `model-*.rb` and `validation-*.rb` [tests](https://github.com/opentox/lazar/tree/master/test).

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

  You can pass training_dataset, prediction_feature and algorithms parameters to the `Model::Validation.create_from_enanomapper` command. Procedure and options are the same as for compounds. The following commands create and validate a `nano-lazar` model with

  - measured P-CHEM properties as descriptors
  - descriptors selected with correlation filter
  - weighted cosine similarity with a threshold of 0.5
  - Caret random forests

```
algorithms = {
  :descriptors => {
    :method => "properties",
    :categories => ["P-CHEM"],
  },
  :similarity => {
    :method => "Algorithm::Similarity.weighted_cosine",
    :min => 0.5
  },
  :feature_selection => {
    :method => "Algorithm::FeatureSelection.correlation_filter",
  },
  :prediction => {
    :method => "Algorithm::Caret.rf",
  },
}
validation_model = Model::Validation.from_enanomapper algorithms: algorithms
```


  Detailed documentation and validation results for nanoparticle models can be found in this [publication](https://github.com/enanomapper/nano-lazar-paper/blob/master/nano-lazar.pdf).

Documentation
-------------
* [API documentation](http://rdoc.info/gems/lazar)

Copyright
---------
Copyright (c) 2009-2017 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
