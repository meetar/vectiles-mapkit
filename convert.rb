# coding: utf-8
# usage: ruby {t} {z} {shapefiles...}
require 'georuby-ext' # gem install georuby-ext
require 'geo_ruby/shp'
require 'fileutils'
require 'json'
include GeoRuby::Shp4r

module Math
  def self.sec(x)
    1.0 / cos(x)
  end
end

module XYZ
  def self.pt2xy(pt, z)
    lnglat2xy(pt.x, pt.y, z)
  end

  def self.lnglat2xy(lng, lat, z)
    n = 2 ** z
    rad = lat * 2 * Math::PI / 360
    [n * ((lng + 180) / 360),
      n * (1 - (Math::log(Math::tan(rad) +
        Math::sec(rad)) / Math::PI)) / 2]
  end

  def self.xyz2lnglat(x, y, z)
    n = 2 ** z
    rad = Math::atan(Math.sinh(Math::PI * (1 - 2.0 * y / n)))
    [360.0 * x / n - 180.0, rad * 180.0 / Math::PI]
  end

  def self.xyz2envelope(x, y, z)
    GeoRuby::SimpleFeatures::Envelope.from_points([
      GeoRuby::SimpleFeatures::Point.from_coordinates(
        xyz2lnglat(x, y, z)),
      GeoRuby::SimpleFeatures::Point.from_coordinates(
        xyz2lnglat(x + 1, y + 1, z))])
  end
end

class GeoRuby::SimpleFeatures::Geometry
  def tile(z)
    lower = XYZ::pt2xy(self.bounding_box[0], z)
    upper = XYZ::pt2xy(self.bounding_box[1], z)
    self.each{|g|
      rg = g.to_rgeo
      lower[0].truncate.upto(upper[0].truncate) {|x|
        upper[1].truncate.upto(lower[1].truncate) {|y|
          env = XYZ::xyz2envelope(x, y, z).to_rgeo
          intersection = rg.intersection(env)
          if intersection.is_empty?
            $stderr.print "e"
            next
          end
          if intersection.respond_to?(:each)
            intersection.each {|g|
              $stderr.print "m"
              yield x, y, JSON.parse(g.to_georuby.as_geojson)
            }
          else
            $stderr.print "s"
            yield x, y, JSON.parse(intersection.to_georuby.as_geojson)
          end
        }
      }
    }
  end
end

def write(geojson, tzxy)
  $stderr.print tzxy.inspect
  path = tzxy.join('/') + '.geojson'
  print "writing #{geojson[:features].size} features to #{path}\n"
  [File.dirname(path)].each {|d| FileUtils.mkdir_p(d) unless File.exist?(d)}
  File.open(path, 'w') {|w| w.print(JSON.dump(geojson))}
end

def map(t, z, paths)
  IO.popen("sort | ruby #{__FILE__}", 'w') {|io|
    fid = 0
    paths.each {|path|
      ShpFile.open(path) {|shp|
        shp.each{|r|
          fid += 1
          prop = r.data.attributes
          prop[:fid] = fid
          $stderr.print "[#{fid}]"
          r.geometry.tile(z) {|x, y, g|
            f = {:type => 'Feature', :geometry => g, :properties => prop}
            io.puts([t, z, x, y, JSON.dump(f)].join("\t") + "\n")
          }
        }
      }
    }
    $stderr.print "\n"
  }
end

def reduce
  last = nil # to extend the scope of the variable
  geojson = nil # to extend the scope of the variable
  while gets
    r = $_.strip.split("\t")
    current = r[0..3]
    if current != last
      write(geojson, last) unless last.nil?
      geojson = {:type => 'FeatureCollection', :features => []}
    end
    geojson[:features] << JSON.parse(r[4])
    last = current
  end
  write(geojson, last)
end

def help
  print <<-EOS
  ruby convert.rb {t} {z} {shapefiles...}
  EOS
end

if __FILE__ == $0
  if ARGV.size == 0
    reduce
  else
    begin
      map(ARGV[0], ARGV[1].to_i, ARGV[2..-1])
    rescue
      p $!
      help
    end
  end
end
