require 'json'

#get list of bundle URIs
`wget 'https://data.enanomapper.net/bundle?media=application%2Fjson' -O bundles.json`
json = JSON.parse File.read('./bundles.json')
json["dataset"].each do |dataset|
  uri = dataset["URI"]
  id = uri.split("/").last
  #`wget --header='accept:application/json' '#{uri}' -O 'bundle#{id}'`
  `wget --header='accept:application/ld+json' '#{uri}/substance' -O 'study#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["summary"]}' -O 'summary#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["compound"]}' -O 'compound#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["substance"]}' -O 'substance#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["property"]}' -O 'property#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["dataset"]}' -O 'dataset#{id}.json'`
  #`wget --header='accept:application/json' '#{dataset["matrix"]}' -O 'matrix#{id}.json'`
end
