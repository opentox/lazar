module OpenTox
  module Algorithm

    class Vector
      def self.dot_product(a, b)
        products = a.zip(b).map{|a, b| a * b}
        products.inject(0) {|s,p| s + p}
      end

      def self.magnitude(point)
        squares = point.map{|x| x ** 2}
        Math.sqrt(squares.inject(0) {|s, c| s + c})
      end
    end

    class Similarity

      def self.tanimoto fingerprints
        ( fingerprints[0] & fingerprints[1]).size/(fingerprints[0]|fingerprints[1]).size.to_f
      end

      def self.euclid scaled_properties
        sq = scaled_properties[0].zip(scaled_properties[1]).map{|a,b| (a - b) ** 2}
        Math.sqrt(sq.inject(0) {|s,c| s + c})
      end

      # http://stackoverflow.com/questions/1838806/euclidean-distance-vs-pearson-correlation-vs-cosine-similarity
      def self.cosine scaled_properties
        scaled_properties = remove_nils scaled_properties
        Algorithm::Vector.dot_product(scaled_properties[0], scaled_properties[1]) / (Algorithm::Vector.magnitude(scaled_properties[0]) * Algorithm::Vector.magnitude(scaled_properties[1]))
      end

      def self.weighted_cosine scaled_properties # [a,b,weights]
        a,b,w = remove_nils scaled_properties
        dot_product = 0
        magnitude_a = 0
        magnitude_b = 0
        (0..a.size-1).each do |i|
          dot_product += w[i].abs*a[i]*b[i]
          magnitude_a += w[i].abs*a[i]**2
          magnitude_b += w[i].abs*b[i]**2
        end
        dot_product/(Math.sqrt(magnitude_a)*Math.sqrt(magnitude_b))
      end

      def self.remove_nils scaled_properties
        a =[]; b = []; w = []
        (0..scaled_properties.first.size-1).each do |i|
          if scaled_properties[0][i] and scaled_properties[1][i] and !scaled_properties[0][i].nan? and !scaled_properties[1][i].nan?
            a << scaled_properties[0][i]
            b << scaled_properties[1][i]
            w << scaled_properties[2][i]
          end
        end
        [a,b,w]
      end

    end
  end
end
