from pyproj import Transformer, Proj
from shapely.geometry import Polygon
from geopy.distance import geodesic

import folium
import math

ZONE_SPLIT_X = 1/6
ZONE_SPLIT_Y = 1/8
SUBZONE_SPLIT_X = 1/64
SUBZONE_SPLIT_Y = 1/128

m = folium.Map()

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

    bounds = bounds | get_latitude_band_boundaries(band)
    print(f"DEBUG: boundaries = {bounds}")

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

def find_1km_area(utm_x, utm_y, utm_zone, lat_band):
    """
    Find the 1km-bloc the point belongs to.
    """

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
    # Get UTM zone, latitude band and convert GPS coords to UTM ones
    utm_zone, lat_band = get_utm_zone(lat, lon)
    print(f"DEBUG: utm zone = {utm_zone}, lat band = {lat_band}")

    corner_x = boundaries["west_lon"]
    corner_y = boundaries["south_lat"]

    # An UTM zone is splitted into 48 subzones of 1 degree lon x 1 degree lat.
    # Each of this subzone is divided into 64 pieces horizontally so that we can
    # have a 64-bit integer as a bitmap to keep track of the area status
    # (do we already have the places inside it or not).
    # Vertically it si splitted into 128 pieces (arbitrary). The bigger distance
    # in km between width and height will be chosen to compute the radius for
    # the request to the Places API.
    area_width = 1 / 64
    area_height = 1 / 128

    # At that point we have the UTM zone/lat band. Next step is to get the
    # subzone coordinates. Reminder: subzones are 1 degree lon x 1 degree lat.
    subzone_x = math.floor(lon)
    subzone_y = math.floor(lat)
    print(f"DEBUG: subzone x = {subzone_x}, subzone y = {subzone_y}")

    # Now we need the coordinates of the area inside that subzone. We need the
    # column index to flip the bitmap accordingly and the row index to know
    # which bitmap to modify. Those bitmaps are integer in the database.
    row = math.floor((lon - corner_x) / SUBZONE_SPLIT_X)
    column = math.floor((lat - corner_y) / SUBZONE_SPLIT_Y)
    print(f"area row = {row}, column = {column}")

    return subzone_x, subzone_y, row, column

def get_area(lat, lon):
    zone, band = get_utm_zone(lat, lon)
    
    bounds = get_utm_zone_boundaries(zone, band)

    subzone_x, subzone_y, area_x, area_y = find_area(bounds, lat, lon)

    # TODO: sql query to get the bitmap (area_y) for the subzone (subzone_x, subzone_y)

    # TODO:
    # - if bit area_x in the bitmap is set, done
    # - else request Places API

    # TODO: bitmap | (1 < column) (after request to Places API)

    return zone, band, subzone_x, subzone_y, area_x, area_y
