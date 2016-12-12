#!/usr/bin/env ruby
require_relative '../lib/lazar'
include OpenTox
Import::Enanomapper.mirror File.join(File.dirname(__FILE__),"..","test","data","enm")
