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

      def self.euclid fingerprints
        sq = fingerprints[0].zip(fingerprints[1]).map{|a,b| (a - b) ** 2}
        Math.sqrt(sq.inject(0) {|s,c| s + c})
      end

      # http://stackoverflow.com/questions/1838806/euclidean-distance-vs-pearson-correlation-vs-cosine-similarity
      def self.cosine fingerprints
        Algorithm::Vector.dot_product(fingerprints[0], fingerprints[1]) / (Algorithm::Vector.magnitude(fingerprints[0]) * Algorithm::Vector.magnitude(fingerprints[1]))
      end

      def self.weighted_cosine fingerprints # [a,b,weights]
        a, b, w = fingerprints
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

    end
  end
end
