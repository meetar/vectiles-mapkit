# coding: utf-8
# usage: ruby {t} {z} {shapefiles...}
require 'rgeo' # gem install rgeo
require 'rgeo/geo_json' # gem install rgeo-geojson
require 'rgeo/shapefile' # gem install rgeo-shapefile
require 'fileutils'
require 'json'

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
    RGeo::GeoJSON.decode(JSON.dump({
      :type => 'Polygon',
      :coordinates => [[
        xyz2lnglat(x, y, z),
        xyz2lnglat(x, y + 1, z),
        xyz2lnglat(x + 1, y + 1, z),
        xyz2lnglat(x + 1, y, z),
        xyz2lnglat(x, y, z)
      ]]
    }), :json_parser => :json)
  end
end

def tile(geom, z)
  lower = nil
  upper = nil
  if(geom.envelope.dimension == 2)
    lower = XYZ::pt2xy(geom.envelope.exterior_ring.point_n(0), z)
    upper = XYZ::pt2xy(geom.envelope.exterior_ring.point_n(2), z)
  else
    lower = XYZ::pt2xy(geom.envelope, z)
    upper = lower
  end
  (geom.respond_to?(:each) ? geom : [geom]).each{|g|
      lower[0].truncate.upto(upper[0].truncate) {|x|
        upper[1].truncate.upto(lower[1].truncate) {|y|
          env = XYZ::xyz2envelope(x, y, z)
          is = env.intersection(g)
          (is.respond_to?(:each) ? is : [is]).each {|g|
            yield x, y, RGeo::GeoJSON.encode(g)
          } if is
        }
      }
    }
  end

def write(geojson, tzxy)
  path = tzxy.join('/') + '.geojson'
  print "writing #{geojson[:features].size} features to #{path}\n"
  [File.dirname(path)].each {|d| FileUtils.mkdir_p(d) unless File.exist?(d)}
  File.open(path, 'w') {|w| w.print(JSON.dump(geojson))}
end

def map(t, z, paths)
  IO.popen("sort | ruby #{__FILE__}", 'w') {|io|
#  [$stdout].each {|io|
    fid = 0
    paths.each {|path|
      RGeo::Shapefile::Reader.open(path) {|shp|
        shp.each{|r|
          fid += 1
          prop = r.attributes
          prop[:fid] = fid
          $stderr.print "[#{fid}]"
          tile(r.geometry, z) {|x, y, g|
            f = {:type => 'Feature', :geometry => g, :properties => prop}
            io.puts([t, z, x, y, JSON.dump(f)].join("\t") + "\n")
          }
        }
      }
    }
  }
end

def reduce
  last = nil
  geojson = nil
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
