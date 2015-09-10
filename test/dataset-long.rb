require_relative "setup.rb"

class DatasetLongTest < MiniTest::Test

  def test_01_upload_epafhm
    f = File.join DATA_DIR, "EPAFHM.csv"
    d = OpenTox::Dataset.from_csv_file f
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_equal csv.size-1, d.data_entries.size
    d.delete
  end

=begin
# TODO catch OpenBabel segfaults and identify/remove cause
  def test_02_upload_multicell
    duplicates = [
      "http://localhost:8082/compound/InChI=1S/C6HCl5O/c7-1-2(8)4(10)6(12)5(11)3(1)9/h12H",
      "http://localhost:8082/compound/InChI=1S/C12H8Cl6O/c13-8-9(14)11(16)5-3-1-2(6-7(3)19-6)4(5)10(8,15)12(11,17)18/h2-7H,1H2",
      "http://localhost:8082/compound/InChI=1S/C2HCl3/c3-1-2(4)5/h1H",
      "http://localhost:8082/compound/InChI=1S/C4H5Cl/c1-3-4(2)5/h3H,1-2H2",
      "http://localhost:8082/compound/InChI=1S/C4H7Cl/c1-4(2)3-5/h1,3H2,2H3",
      "http://localhost:8082/compound/InChI=1S/C8H14O4/c1-5-4-8(11-6(2)9)12-7(3)10-5/h5,7-8H,4H2,1-3H3",
      "http://localhost:8082/compound/InChI=1S/C19H30O5/c1-3-5-7-20-8-9-21-10-11-22-14-17-13-19-18(23-15-24-19)12-16(17)6-4-2/h12-13H,3-11,14-15H2,1-2H3",
    ]
    errors = ['O=P(H)(OC)OC', 'C=CCNN.HCl' ]
    f = File.join DATA_DIR, "multi_cell_call.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal true, d.features.first.nominal
    assert_nil d["index"]
    assert_equal csv.size-1-errors.size, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_equal csv.size-1-errors.size, d.data_entries.size
    p d.warnings
    (duplicates+errors).each do |uri|
      assert d.warnings.grep %r{#{uri}}
    end
    d.delete
  end
=end

  def test_03_upload_isscan
    f = File.join DATA_DIR, "ISSCAN-multi.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_equal csv.size-1, d.data_entries.size
    d.delete
    #assert_equal false, URI.accessible?(d.uri)
  end

  def test_04_simultanous_upload
    threads = []
    3.times do |t|
      threads << Thread.new(t) do |up|
        d = OpenTox::Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
        assert_equal OpenTox::Dataset, d.class
        assert_equal 1, d.features.size
        assert_equal 85, d.compounds.size
        assert_equal 85, d.data_entries.size
        csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
        csv.shift
        assert_equal csv.collect{|r| r[1]}, d.data_entries.flatten
        d.delete 
      end
    end
    threads.each {|aThread| aThread.join}
  end

  def test_05_upload_kazius
    f = File.join DATA_DIR, "kazius.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_equal csv.size-1, d.data_entries.size
    assert_empty d.warnings
    #  493 COC1=C(C=C(C(=C1)Cl)OC)Cl,1
    c = d.compounds[491]
    assert_equal c.smiles, "COc1cc(Cl)c(cc1Cl)OC"
    assert_equal d.data_entries[491][0], "1"
    d.delete
  end

  def test_upload_feature_dataset
    t = Time.now
    f = File.join DATA_DIR, "rat_feature_dataset.csv"
    d = Dataset.from_csv_file f
    assert_equal 458, d.features.size
    d.save
    #p "Upload: #{Time.now-t}"
    d2 = Dataset.find d.id
    t = Time.now
    assert_equal d.features.size, d2.features.size
    csv = CSV.read f
    csv.shift # remove header
    assert_empty d2.warnings
    assert_equal csv.size, d2.compounds.size 
    assert_equal csv.first.size-1, d2.features.size
    d2.compounds.each_with_index do |compound,i|
      row = csv[i]
      row.shift # remove compound
      assert_equal row, d2.data_entries[i]
    end
    #p "Dowload: #{Time.now-t}"
    d2.delete
    assert_nil Dataset.find d.id
  end

end
