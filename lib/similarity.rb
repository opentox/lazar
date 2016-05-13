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

      def self.tanimoto a, b
        ( a & b).size/(a|b).size.to_f
      end

      def self.euclid a, b
        sq = a.zip(b).map{|a,b| (a - b) ** 2}
        Math.sqrt(sq.inject(0) {|s,c| s + c})
      end

      # http://stackoverflow.com/questions/1838806/euclidean-distance-vs-pearson-correlation-vs-cosine-similarity
      def self.cosine a, b
        Algorithm::Vector.dot_product(a, b) / (Algorithm::Vector.magnitude(a) * Algorithm::Vector.magnitude(b))
      end

      def self.weighted_cosine(a, b, w)
        dot_product = 0
        magnitude_a = 0
        magnitude_b = 0
        (0..a.size-1).each do |i|
          dot_product += w[i].abs*a[i]*b[i]
          magnitude_a += w[i].abs*a[i]**2
          magnitude_b += w[i].abs*b[i]**2
        end
        dot_product/Math.sqrt(magnitude_a*magnitude_b)
      end

    end
  end
end
