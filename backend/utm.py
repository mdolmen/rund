from pyproj import Transformer, Proj
from shapely.geometry import Polygon
from geopy.distance import geodesic

import folium
import math

SUBZONE_SPLIT_X = 64
SUBZONE_SPLIT_Y = 128

# An UTM zone is splitted into 48 subzones of 1 degree lon x 1 degree lat.
# Each of this subzone is divided into 64 pieces horizontally and 128
# vertically (arbitrary). The bigger distance in km between width and height
# will be chosen to compute the radius for the request to the Places API.
AREA_WIDTH = 1 / SUBZONE_SPLIT_X
AREA_HEIGHT = 1 / SUBZONE_SPLIT_Y

m = folium.Map()

class PointInfo:
    def __init__(self, zone, band, subzone_lon, subzone_lat, area_x, area_y):
        self.zone = zone
        self.band = band
        self.subzone_lon = subzone_lon
        self.subzone_lat = subzone_lat
        self.area_x = area_x
        self.area_y = area_y
        self.area_center_lon = -1
        self.area_center_lat = -1

    def set_center(self, lon, lat):
        self.area_center_lon = lon
        self.area_center_lat = lat

def init_utm_transformer(utm_zone, lat_band):
    """
    Init a transformer to convert coords from GPS to UTM.
    """
    utm_crs = f"EPSG:{32600 + utm_zone}" if lat_band >= 'N' else f"EPSG:{32700 + utm_zone}"
    transformer = Transformer.from_crs("EPSG:4326", utm_crs)
    return transformer

def init_gps_transformer(utm_zone, lat_band):
    """
    Init a transformer to convert coords from UTM to GPS.
    """
    utm_crs = f"EPSG:{32600 + utm_zone}" if lat_band >= 'N' else f"EPSG:{32700 + utm_zone}"
    transformer = Transformer.from_crs(utm_crs, "EPSG:4326")
    return transformer

def get_utm_zone_boundaries(zone, band):
    """
    Calculate the geographic boundaries of a given UTM zone.

    :param zone: The UTM zone number with the latitude band (e.g. 32).
    :param band: The latitude band.

    :return: Dictionary with boundaries (west_lon, east_lon, south_lat, north_lat).
    """
    south = "CDEFGHJKLM"
    hemisphere = 'S' if band in south else 'N'
    bounds = {}

    # Validate input
    if not 1 <= zone <= 60:
        raise ValueError("UTM zone number must be between 1 and 60.")
    if hemisphere not in ('N', 'S'):
        raise ValueError("Hemisphere must be 'N' or 'S'.")

    # Longitude boundaries
    central_meridian = (zone - 1) * 6 - 180 + 3
    bounds["west_lon"] = central_meridian - 3
    bounds["east_lon"] = central_meridian + 3

    # Get and combine north/south bounds with east/west ones
    bounds = bounds | get_latitude_band_boundaries(band)

    return bounds

def get_latitude_band_boundaries(band_letter):
    """
    Calculate the geographic boundaries of a given UTM latitude band.

    :param band_letter: The latitude band letter.
    :return: Dictionary with boundaries (south_lat, north_lat).
    """
    # Validate input
    if band_letter not in "CDEFGHJKLMNPQRSTUVWX":
        raise ValueError("Invalid latitude band letter.")

    # Latitude bands 'C' to 'X'
    lat_band_ranges = {
        'C': (-80, -72),
        'D': (-72, -64),
        'E': (-64, -56),
        'F': (-56, -48),
        'G': (-48, -40),
        'H': (-40, -32),
        'J': (-32, -24),
        'K': (-24, -16),
        'L': (-16, -8),
        'M': (-8, 0),
        'N': (0, 8),
        'P': (8, 16),
        'Q': (16, 24),
        'R': (24, 32),
        'S': (32, 40),
        'T': (40, 48),
        'U': (48, 56),
        'V': (56, 64),
        'W': (64, 72),
        'X': (72, 84)
    }

    south_lat, north_lat = lat_band_ranges[band_letter]

    return {
        "south_lat": south_lat,
        "north_lat": north_lat
    }

def get_utm_zone(lat, lon):
    """
    Get the UTM zone a GPS point belongs to and convert its coords to the UTM system.
    Details about UTM and list of exceptions: https://www.smallfarmlink.org/education/utm.

    :param lat: Latitude.
    :param lon: Longitude.

    :return: UTM zone and latitude band.
    """
    # Check that lat/lon are valid coordinates
    invalid = (0, 'A')
    if lat < -80 or lat > 84:
        return invalid
    if lon < -180 or lon > 180:
        return invalid

    # Determine the UTM zone
    utm_zone = int((lon + 180) / 6) + 1

    # Determine the latitude band
    lat_band_letters = "CDEFGHJKLMNPQRSTUVWX"

    # Handle special case for latitude band 'X' (72°N to 84°N)
    if lat >= 72:
        lat_band = 'X'
    else:
        lat_band = lat_band_letters[int((lat + 80) / 8)]

    # Handle special exceptions for certain zones and bands
    if lat_band == 'X' and 72 <= lat < 84:  # Special handling for band 'X'
        if 9 <= lon < 21:
            utm_zone = 31  # Zone 31X
        elif 21 <= lon < 33:
            utm_zone = 33  # Zone 33X
        elif 33 <= lon < 42:
            utm_zone = 35  # Zone 35X
        elif lon >= 42:
            utm_zone = 37  # Zone 37X

    # Handle the special case of zone 32V (West coast of Norway)
    if lat_band == 'V' and 56 <= lat < 64 and 3 <= lon < 12:
        utm_zone = 32  # Zone 32V expanded from 6° to 9°

    # Handle the narrowing of zone 31V due to expansion of 32V
    if lat_band == 'V' and 56 <= lat < 64 and lon < 3:
        utm_zone = 31  # Zone 31V

    return utm_zone, lat_band

def find_area(boundaries, lat, lon):
    """
    Identify the small area the point belongs to. Area here refers to the basic
    zone we'll get places for. We keep track of what areas are covered (i.e.
    places have been gathered for it).

    :param gps_transformer: Transformer for conversion UTM to GPS.
    :param utm_transformer: Transformer for conversion GPS to UTM.
    :param boundaries: The boundaries of an UTM zone.
    :param lat: Latitude of the point.
    :param lon: Longitude of the point.

    :return: The coordinates of the subzone and the coords of the area within
    the virtually splitted map.
    """
    # Get UTM zone and latitude band
    utm_zone, lat_band = get_utm_zone(lat, lon)

    # At that point we have the UTM zone/lat band. Next step is to get the
    # subzone coordinates. Reminder: subzones are 1 degree lon x 1 degree lat.
    subzone_lon = math.floor(lon)
    subzone_lat = math.floor(lat)

    # Now we need the coordinates of the area inside that subzone. We need the
    # column index to flip the bitmap accordingly and the row index to know
    # which bitmap to modify. Those bitmaps are integer in the database.
    # (area_x, area_y) is the corner of the area. We need to return the width and
    # hieght of the area to latter compute the center of the area.
    area_x = math.floor((lon - subzone_lon) / AREA_WIDTH)
    area_y = math.floor((lat - subzone_lat) / AREA_HEIGHT)

    return subzone_lon, subzone_lat, area_x, area_y

def get_area(lat, lon):
    zone, band = get_utm_zone(lat, lon)
    
    bounds = get_utm_zone_boundaries(zone, band)

    subzone_lon, subzone_lat, area_x, area_y = find_area(bounds, lat, lon)

    return PointInfo(zone, band, subzone_lon, subzone_lat, area_x, area_y)

def longitude_diff_to_km(lat, lon_start, lon_end):
    """
    Convert a change in longitude at a specific latitude to a distance in kilometers.

    :param lat: Latitude where the distance is measured.
    :param lon_start: Starting longitude.
    :param lon_end: Ending longitude.
    :return: Distance in kilometers.
    """
    point_start = (lat, lon_start)
    point_end = (lat, lon_end)
    return geodesic(point_start, point_end).kilometers

def latitude_diff_to_km(lat_start, lat_end, lon):
    """
    Convert a change in latitude at a specific longitude to a distance in kilometers.

    :param lat_start: Starting latitude.
    :param lat_end: Ending latitude.
    :param lon: Longitude where the distance is measured.
    :return: Distance in kilometers.
    """
    point_start = (lat_start, lon)
    point_end = (lat_end, lon)
    return geodesic(point_start, point_end).kilometers
