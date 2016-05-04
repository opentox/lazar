require_relative '../lib/lazar'
include OpenTox
$mongo.database.drop
$gridfs = $mongo.database.fs # recreate GridFS indexes
Import::Enanomapper.import
`mongodump -h 127.0.0.1 -d production`
