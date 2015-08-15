import joelib2.feature.FeatureHelper;

class JoelibDescriptorInfo {
  public static void main(String[] args) {
    FeatureHelper helper = FeatureHelper.instance();
    System.out.println("---"); // document separator for Joelib debug messages
    for (Object feature : helper.getNativeFeatures() ) {
      System.out.println("- :java_class: \""+feature.toString()+"\"");
      // methods for accessing feature descriptions e.g. with 
      // FeatureFactory.instance().getFeature(feature.toString()).getDescription().getText() or
      // FeatureFactory.instance().getFeature(feature.toString()).getDescription().getHtml()
      // are defunct
    }
  }
}
