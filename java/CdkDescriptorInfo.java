import java.util.*;
import org.openscience.cdk.DefaultChemObjectBuilder;
import org.openscience.cdk.qsar.*;
//import org.openscience.cdk.qsar.descriptors.molecular.*;

class CdkDescriptorInfo {
  public static void main(String[] args) {

    DescriptorEngine engine = new DescriptorEngine(IMolecularDescriptor.class,null);

    for (Iterator<IDescriptor> it = engine.getDescriptorInstances().iterator(); it.hasNext(); ) {
      IDescriptor descriptor = it.next();
      String cdk_class = descriptor.getClass().toString().replaceAll("class ","");
      System.out.println("- :java_class: \""+cdk_class+"\"");
      String description = engine.getDictionaryDefinition(cdk_class).replaceAll("^\\s+", "" ).replaceAll("\\s+$", "").replaceAll("\\s+", " ");
      System.out.println("  :description: \""+description+"\"");
      System.out.println("  :names:");
      for (String name : descriptor.getDescriptorNames()) {
        System.out.println("    - \""+name+"\"");
      }
    }
  }
}
