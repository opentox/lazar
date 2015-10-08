import java.util.*;
import java.io.*;
import org.openscience.cdk.DefaultChemObjectBuilder;
import org.openscience.cdk.interfaces.IMolecule;
import org.openscience.cdk.io.iterator.IteratingMDLReader;
import org.openscience.cdk.qsar.*;
import org.openscience.cdk.qsar.DescriptorValue;
import org.openscience.cdk.aromaticity.CDKHueckelAromaticityDetector;
import org.openscience.cdk.tools.manipulator.AtomContainerManipulator;
import org.openscience.cdk.exception.NoSuchAtomTypeException;

class CdkDescriptors {
  public static void main(String[] args) {

    if (args==null || args.length<2) {
	System.err.println("required params: <sd-file> <descriptor1> <descriptor2(optional)> <descriptor3(optional)> ...");
	System.exit(1);
    }
    if (! new File(args[0]).exists()){
	System.err.println("file not found "+args[0]);
	System.exit(1);
    }

    // command line descriptor params can be either "descriptorName" or "descriptorValueName"
    // terminology:
    // A descriptor can calculate serveral values, e.g., ALOGP produces ALOGP.ALogP, ALOGP.ALogp2, ALOGP.AMR
    // "descriptorName" ALOGP
    // "valueName" AMR
    // "descriptorValueName" ALOGP.AMR
    DescriptorEngine engine;
    Set<String> classNames = new LinkedHashSet<String>(); // descriptors to be computed
    Set<String> descriptorNames = new LinkedHashSet<String>(); // all values of this descriptor will be printed
    Set<String> descriptorValueNames = new LinkedHashSet<String>(); // only these values of a descriptor will be printed
    for (int i =1; i < args.length; i++) {
      String descriptorName;
      if (args[i].indexOf(".")!=-1) {
          descriptorValueNames.add(args[i]);
	  descriptorName = args[i].substring(0,args[i].indexOf("."));
      }
      else {
	  descriptorNames.add(args[i]);
          descriptorName = args[i];
      }
      classNames.add(getDescriptorClassName(descriptorName));
    }

    engine = new DescriptorEngine(new ArrayList<String>(classNames));
    List<IDescriptor> instances =  engine.instantiateDescriptors(new ArrayList<String>(classNames));
    List<DescriptorSpecification> specs = engine.initializeSpecifications(instances);
    engine.setDescriptorInstances(instances);
    engine.setDescriptorSpecifications(specs);

    try {
      BufferedReader br = new BufferedReader(new FileReader(args[0]));
      PrintWriter yaml = new PrintWriter(new FileWriter(args[0]+"cdk.yaml"));
      // parse 3d sdf from file and calculate descriptors
      IteratingMDLReader reader = new IteratingMDLReader( br, DefaultChemObjectBuilder.getInstance());
      int c = 0;
      while (reader.hasNext()) {
        try {
          System.out.println("computing "+(args.length-1)+" descriptors for compound "+(++c));
          IMolecule molecule = (IMolecule)reader.next();
          molecule = (IMolecule) AtomContainerManipulator.removeHydrogens(molecule);
          try {
            AtomContainerManipulator.percieveAtomTypesAndConfigureAtoms(molecule);
          }
	      catch (NoSuchAtomTypeException e) {
            e.printStackTrace();
          }
          CDKHueckelAromaticityDetector.detectAromaticity(molecule);

          engine.process(molecule);
          Map<Object,Object> properties = molecule.getProperties();
          Boolean first = true;
          for (Map.Entry<Object, Object> entry : properties.entrySet()) {
            try {
              if ((entry.getKey() instanceof DescriptorSpecification) && (entry.getValue() instanceof DescriptorValue)) {
                DescriptorSpecification property = (DescriptorSpecification)entry.getKey();
                DescriptorValue value = (DescriptorValue)entry.getValue();
                String[] values = value.getValue().toString().split(",");
                for (int i = 0; i < values.length; i++) {
                  String cdk_class = property.getImplementationTitle();
                  String descriptorName = cdk_class.substring(cdk_class.lastIndexOf(".")+1).replace("Descriptor","");
                  String descriptorValueName = descriptorName + "." + value.getNames()[i];
		  if (descriptorNames.contains(descriptorName) || descriptorValueNames.contains(descriptorValueName)) {
		      if (first) { yaml.print("- "); first = false; }
		      else { yaml.print("  "); }
                      yaml.println("Cdk." + descriptorValueName  + ": " + values[i]);
		  }
                }
              }
            }
            catch (ClassCastException e) { } // sdf properties are stored as molecules properties (strings), ignore them
            catch (Exception e) { e.printStackTrace(); } // output nothing to yaml
          }
        }
        catch (Exception e) {
          yaml.println("- {}");
          e.printStackTrace();
          continue;
        }
      }
      yaml.close();
    }
    catch (Exception e) { e.printStackTrace(); }
  }
    

    /** HACK to find the class for a descriptor
     * problem: Descriptor is not always at the end of the class (APolDescriptor), but may be in the middle (AutocorrelationDescriptorPolarizability)
     * this method makes a class-lookup using trial and error */
    static String getDescriptorClassName(String descriptorName) {
	String split = splitCamelCase(descriptorName)+" "; // space mark possible positions for 'Descriptor'
	for(int i = split.length()-1; i>0; i--) {
	    if (split.charAt(i)==' ') { // iterate over all spaces, starting with the trailing one
		String test = split.substring(0,i)+"Descriptor"+split.substring(i+1,split.length()); // replace current space with 'Descriptor' ..
		test = test.replaceAll("\\s",""); // .. and remove other spaces
		String className = "org.openscience.cdk.qsar.descriptors.molecular." + test;
		try {
		    Class.forName(className);
		    return className;
		} catch (ClassNotFoundException e) {}
	    }
        }
	System.err.println("Descriptor not found: "+descriptorName);
	System.exit(1);
	return null;
    }

    /** inserts space in between camel words */
  static String splitCamelCase(String s) {
   return s.replaceAll(
      String.format("%s|%s|%s",
         "(?<=[A-Z])(?=[A-Z][a-z])",
         "(?<=[^A-Z])(?=[A-Z])",
         "(?<=[A-Za-z])(?=[^A-Za-z])"
      ),
      " "
   );
  }
}
