import java.util.*;
import java.io.*;
import joelib2.feature.Feature;
import joelib2.feature.FeatureHelper;
import joelib2.feature.FeatureFactory;
import joelib2.feature.FeatureResult;
import joelib2.io.BasicIOType;
import joelib2.io.BasicIOTypeHolder;
import joelib2.io.BasicReader;
import joelib2.io.MoleculeFileHelper;
import joelib2.io.MoleculeFileIO;
import joelib2.io.MoleculeIOException;
import joelib2.molecule.BasicConformerMolecule;

class JoelibDescriptors {
  public static void main(String[] args) {

    String[] features = null;
    features = new String[args.length-1];
    System.arraycopy(args,1,features,0,args.length-1);

    FeatureFactory factory = FeatureFactory.instance();
    MoleculeFileIO loader = null;
    String line = new String();
    String sdf = new String();
    try {
      // parse 3d sdf from file and calculate descriptors
      InputStream is = new FileInputStream(args[0]);
      PrintWriter yaml = new PrintWriter(new FileWriter(args[0]+"joelib.yaml"));
      BasicIOType inType = BasicIOTypeHolder.instance().getIOType("SDF");
      loader = MoleculeFileHelper.getMolReader(is, inType);
      BasicConformerMolecule mol = new BasicConformerMolecule(inType, inType);
      while (true) {
        try {
          Boolean success = loader.read(mol);
          if (!success) { break; } // last molecule
          for (int i =0; i < features.length; i++) {
            String name = "joelib2.feature.types." + features[i];
            Feature feature = factory.getFeature(name);
            FeatureResult result = feature.calculate(mol);
            if (i == 0) { yaml.print("- "); }
            else { yaml.print("  "); }
            yaml.print( "Joelib."+features[i]+": " );
            yaml.println( result.toString() );
          }

        }
        catch (Exception e) { 
          System.err.println(e.toString());
          e.printStackTrace();
        }
      }
      yaml.close();
    }
    catch (Exception e) {
      System.err.println(e.toString());
      e.printStackTrace();
    }
  }
}
