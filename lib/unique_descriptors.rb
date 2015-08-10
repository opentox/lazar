# set of non redundant descriptors, faster algorithms are preferred
# TODO:
# select logP algorithm
# select l5 algorithm
# use smarts matcher for atom counts
# check correlations
UNIQUEDESCRIPTORS = [
  "Openbabel.abonds", #Number of aromatic bonds
  "Openbabel.atoms", #Number of atoms
  "Openbabel.bonds", #Number of bonds
  "Openbabel.dbonds", #Number of double bonds
  "Openbabel.HBA1", #Number of Hydrogen Bond Acceptors 1 (JoelLib)
  "Openbabel.HBA2", #Number of Hydrogen Bond Acceptors 2 (JoelLib)
  "Openbabel.HBD", #Number of Hydrogen Bond Donors (JoelLib)
  "Openbabel.L5", #Lipinski Rule of Five
  "Openbabel.logP", #octanol/water partition coefficient
  "Openbabel.MP", #Melting point
  "Openbabel.MR", #molar refractivity
  "Openbabel.MW", #Molecular Weight filter
  "Openbabel.nF", #Number of Fluorine Atoms
  "Openbabel.sbonds", #Number of single bonds
  "Openbabel.tbonds", #Number of triple bonds
  "Openbabel.TPSA", #topological polar surface area
  "Cdk.ALOGP", #Calculates atom additive logP and molar refractivity values as described by Ghose and Crippen and
  "Cdk.APol", #Descriptor that calculates the sum of the atomic polarizabilities (including implicit hydrogens).
  "Cdk.AcidicGroupCount", #Returns the number of acidic groups.
  "Cdk.AminoAcidCount", #Returns the number of amino acids found in the system
  #"Cdk.AromaticAtomsCount", #Descriptor based on the number of aromatic atoms of a molecule.
  #"Cdk.AromaticBondsCount", #Descriptor based on the number of aromatic bonds of a molecule.
  #"Cdk.AtomCount", #Descriptor based on the number of atoms of a certain element type.
  "Cdk.AutocorrelationCharge", #The Moreau-Broto autocorrelation descriptors using partial charges
  "Cdk.AutocorrelationMass", #The Moreau-Broto autocorrelation descriptors using atomic weight
  "Cdk.AutocorrelationPolarizability", #The Moreau-Broto autocorrelation descriptors using polarizability
  "Cdk.BCUT", #Eigenvalue based descriptor noted for its utility in chemical diversity described by Pearlman et al. .
  "Cdk.BPol", #Descriptor that calculates the sum of the absolute value of the difference between atomic polarizabilities of all bonded atoms in the molecule (including implicit hydrogens).
  "Cdk.BasicGroupCount", #Returns the number of basic groups.
  #"Cdk.BondCount", #Descriptor based on the number of bonds of a certain bond order.
  "Cdk.CPSA", #A variety of descriptors combining surface area and partial charge information
  "Cdk.CarbonTypes", #Characterizes the carbon connectivity in terms of hybridization
  "Cdk.ChiChain", #Evaluates the Kier & Hall Chi chain indices of orders 3,4,5 and 6
  "Cdk.ChiCluster", #Evaluates the Kier & Hall Chi cluster indices of orders 3,4,5,6 and 7
  "Cdk.ChiPathCluster", #Evaluates the Kier & Hall Chi path cluster indices of orders 4,5 and 6
  "Cdk.ChiPath", #Evaluates the Kier & Hall Chi path indices of orders 0,1,2,3,4,5,6 and 7
  "Cdk.EccentricConnectivityIndex", #A topological descriptor combining distance and adjacency information.
  "Cdk.FMF", #Descriptor characterizing molecular complexity in terms of its Murcko framework
  "Cdk.FragmentComplexity", #Class that returns the complexity of a system. The complexity is defined as @cdk.cite{Nilakantan06}
  "Cdk.GravitationalIndex", #Descriptor characterizing the mass distribution of the molecule.
  #"Cdk.HBondAcceptorCount", #Descriptor that calculates the number of hydrogen bond acceptors.
  #"Cdk.HBondDonorCount", #Descriptor that calculates the number of hydrogen bond donors.
  "Cdk.HybridizationRatio", #Characterizes molecular complexity in terms of carbon hybridization states.
  "Cdk.IPMolecularLearning", #Descriptor that evaluates the ionization potential.
  "Cdk.KappaShapeIndices", #Descriptor that calculates Kier and Hall kappa molecular shape indices.
  "Cdk.KierHallSmarts", #Counts the number of occurrences of the E-state fragments
  "Cdk.LargestChain", #Returns the number of atoms in the largest chain
  "Cdk.LargestPiSystem", #Returns the number of atoms in the largest pi chain
  "Cdk.LengthOverBreadth", #Calculates the ratio of length to breadth.
  "Cdk.LongestAliphaticChain", #Returns the number of atoms in the longest aliphatic chain
  "Cdk.MDE", #Evaluate molecular distance edge descriptors for C, N and O
  "Cdk.MannholdLogP", #Descriptor that calculates the LogP based on a simple equation using the number of carbons and hetero atoms .
  "Cdk.MomentOfInertia", #Descriptor that calculates the principal moments of inertia and ratios of the principal moments. Als calculates the radius of gyration.
  "Cdk.PetitjeanNumber", #Descriptor that calculates the Petitjean Number of a molecule.
  "Cdk.PetitjeanShapeIndex", #The topological and geometric shape indices described Petitjean and Bath et al. respectively. Both measure the anisotropy in a molecule.
  "Cdk.RotatableBondsCount", #Descriptor that calculates the number of nonrotatable bonds on a molecule.
  #"Cdk.RuleOfFive", #This Class contains a method that returns the number failures of the Lipinski's Rule Of Five.
  #"Cdk.TPSA", #Calculation of topological polar surface area based on fragment contributions .
  "Cdk.VABC", #Describes the volume of a molecule.
  "Cdk.VAdjMa", #Descriptor that calculates the vertex adjacency information of a molecule.
  "Cdk.WHIM", #Holistic descriptors described by Todeschini et al .
  #"Cdk.Weight", #Descriptor based on the weight of atoms of a certain element type. If no element is specified, the returned value is the Molecular Weight
  "Cdk.WeightedPath", #The weighted path (molecular ID) descriptors described by Randic. They characterize molecular branching.
  "Cdk.WienerNumbers", #This class calculates Wiener path number and Wiener polarity number.
  "Cdk.XLogP", #Prediction of logP based on the atom-type method called XLogP.
  "Cdk.ZagrebIndex", #The sum of the squared atom degrees of all heavy atoms.
  "Joelib.count.NumberOfS", #no description available
  "Joelib.count.NumberOfP", #no description available
  "Joelib.count.NumberOfO", #no description available
  "Joelib.count.NumberOfN", #no description available
  #"Joelib.count.AromaticBonds", #no description available
  "Joelib.count.NumberOfI", #no description available
  "Joelib.count.NumberOfF", #no description available
  "Joelib.count.NumberOfC", #no description available
  "Joelib.count.NumberOfB", #no description available
  "Joelib.count.HydrophobicGroups", #no description available
  #"Joelib.KierShape3", #no description available
  #"Joelib.KierShape2", #no description available
  #"Joelib.KierShape1", #no description available
  #"Joelib.count.AcidicGroups", #no description available
  "Joelib.count.AliphaticOHGroups", #no description available
  #"Joelib.count.NumberOfAtoms", #no description available
  "Joelib.TopologicalRadius", #no description available
  "Joelib.GeometricalShapeCoefficient", #no description available
  #"Joelib.MolecularWeight", #no description available
  "Joelib.FractionRotatableBonds", #no description available
  #"Joelib.count.HBD2", #no description available
  #"Joelib.count.HBD1", #no description available
  "Joelib.LogP", #no description available
  "Joelib.GraphShapeCoefficient", #no description available
  "Joelib.count.BasicGroups", #no description available
  #"Joelib.count.RotatableBonds", #no description available
  "Joelib.count.HeavyBonds", #no description available
  "Joelib.PolarSurfaceArea", #no description available
  #"Joelib.ZagrebIndex1", #no description available
  "Joelib.GeometricalRadius", #no description available
  "Joelib.count.SO2Groups", #no description available
  "Joelib.count.AromaticOHGroups", #no description available
  "Joelib.GeometricalDiameter", #no description available
  #"Joelib.MolarRefractivity", #no description available
  "Joelib.count.NumberOfCl", #no description available
  "Joelib.count.OSOGroups", #no description available
  "Joelib.count.NumberOfBr", #no description available
  "Joelib.count.NO2Groups", #no description available
  "Joelib.count.HeteroCycles", #no description available
  #"Joelib.count.HBA2", #no description available
  #"Joelib.count.HBA1", #no description available
  #"Joelib.count.NumberOfBonds", #no description available
  "Joelib.count.SOGroups", #no description available
  "Joelib.TopologicalDiameter", #no description available
  "Joelib.count.NumberOfHal", #no description available

].sort
