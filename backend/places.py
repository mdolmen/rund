import json
import requests
import httpx
import asyncio
import builtins

from pydantic import BaseModel
from fastapi import HTTPException
from enum import Enum

import utm

from utm import AREA_WIDTH, AREA_HEIGHT, PointInfo
from db import Database

API_KEY_GPLACES = ""

PLACE_TYPES_GAPI = {
    "Automotive": 0,
    "Business": 1,
    "Culture": 2,
    "Education": 3,
    "Entertainment and Recreation": 4,
    "Finance": 5,
    "Food and Drink": 6,
    "Geographical Areas": 7,
    "Government": 8,
    "Health and Wellness": 9,
    "Lodging": 10,
    "Places of Worship": 11,
    "Services": 12,
    "Shopping": 13,
    "Sports": 14,
    "Transportation": 15,
}

PLACE_TYPES_OAPI = {
    "Sustenance": 0,
    "Education": 1,
    "Transportation": 2,
    "Financial": 3,
    "Healthcare": 4,
    "Entertainment Arts Culture": 5,
    "Public Service": 6,
    "Facilities": 7,
    "Waste Management": 8,
    "Others": 9
}

PLACE_TYPES = PLACE_TYPES_OAPI

# Limit of places we can get from a single request
RESULTS_LIMIT_GAPI = 20

# Limit of places we can get from a single request (Overpass API)
RESULTS_LIMIT_OAPI = 50000

class Location(BaseModel):
    latitude: float
    longitude: float

class Circle(BaseModel):
    center: Location
    radius: float

class LocationRestriction(BaseModel):
    circle: Circle

# Params expected by the Google Places API
class RequestBody(BaseModel):
    includedTypes: list[str]
    rankPreference: str
    locationRestriction: LocationRestriction

# Params expected by the Overpass API
class RequestBodyOAPI(BaseModel):
    includedTypes: list[str]
    locationRestriction: LocationRestriction

class AutourRequest(BaseModel):
    includedTypes: list[str]
    rankPreference: str
    locationRestriction: LocationRestriction
    placesType: str
    userId: str

class Places:
    def __init__(self):
        self.db = Database()

    def subzone_exists(self, longitude, latitude):
        return self.db.get_subzone(longitude, latitude)

    def add_subzone_in_zone(self, longitude, latitude, number, band):
        # Get zone id
        zone_id = self.db.get_zone_id(number, band)
        if zone_id == 0:
            return

        # Insert subzone
        print(f"DEBUG: insert_subzone, {longitude}, {latitude}, {zone_id}")
        subzone_id = self.db.insert_subzone(longitude, latitude, zone_id)
        if subzone_id == 0:
            return

        # Create areas
        self.db.insert_areas(subzone_id)

        return subzone_id

    def add_place_gapi(self, place, area_id):
        # format: housenumber street, postcode city, country
        formatted_address = place.get("formattedAddress", "")
        google_maps_uri = place.get("googleMapsUri", "")
        primary_type = place.get("primaryType", "")
        display_name_tmp = place.get("displayName", "")
        display_name = display_name_tmp.get("text", "")
        longitude = place.get("location", {}).get("longitude", 0.0)
        latitude = place.get("location", {}).get("latitude", 0.0)
        current_opening_hours = place.get("currentOpeningHours", "")
        current_opening_hours = json.dumps(current_opening_hours, ensure_ascii=False)
        country_id = self.db.get_country_id(place["formattedAddress"].split(" ")[-1])

        self.db.insert_place(
            formatted_address,
            google_maps_uri,
            primary_type,
            display_name,
            longitude,
            latitude,
            current_opening_hours,
            country_id,
            area_id
        )

        return

    def add_place_oapi(self, place, area_id):
        # format: housenumber street, postcode city, country
        tags = place.get('tags', {})
        print(place)
        print(tags)

        print(tags.get("addr:country", "XX"))
        country = self.db.get_country_name(tags.get("addr:country", "XX"))
        print(country)
        country_id = 0
        if country != "":
            country_id = self.db.get_country_id(country)
        print(country_id)

        formatted_address = tags.get("addr:housenumber", "")
        formatted_address += " " + tags.get("addr:street", "Unknown")
        formatted_address += ", " + tags.get("addr:postcode", "Unknown")
        formatted_address += " " + tags.get("addr:city", "Unknown")
        formatted_address += ", " + country

        google_maps_uri = ""
        primary_type = tags.get("amenity", "")
        display_name = tags.get("name", "")
        longitude = place.get("lon", 0.0)
        latitude = place.get("lat", 0.0)
        current_opening_hours = tags.get("opening_hours", "")
        current_opening_hours = json.dumps(current_opening_hours, ensure_ascii=False)

        self.db.insert_place(
            formatted_address,
            google_maps_uri,
            primary_type,
            display_name,
            longitude,
            latitude,
            current_opening_hours,
            country_id,
            area_id
        )

        return

    def add_places(self, places, places_type, area_id):
        for place in places:
            #self.add_place_gapi(place, area_id)
            self.add_place_oapi(place, area_id)

        # update the bitmap of area covered by place type
        bitmap = self.db.get_area_covered(area_id)
        new_bitmap = bitmap | (1 << PLACE_TYPES[places_type])
        self.db.set_area_covered(area_id, new_bitmap)

    def get_places_from_db(self, area_id, types):
        return self.db.get_places(area_id, types)

    def get_area(self, x, y):
        return self.db.get_area(x, y)

    def get_area_by_id(self, area_id):
        return self.db.get_area_by_id(area_id)

    def get_area_id(self, subzone_lon, subzone_lat, x, y):
        return self.db.get_area_id(subzone_lon, subzone_lat, x, y)

    def is_area_covered(self, area_id, places_type):
        bitmap = self.db.get_area_covered(area_id)
        return (bitmap & (1 << PLACE_TYPES[places_type]))

    def create_subzones_and_areas(self, zone, band):
        return self.db.create_subzones_and_areas(zone, band)

    def insert_purchase(self, user_id, amount):
        return self.db.insert_purchase(user_id, amount)

    def insert_credits(self, user_id, credits):
        return self.db.insert_credits(user_id, credits)

    def get_credits(self, user_id):
        return self.db.get_credits(user_id)

    def inc_credits(self, user_id):
        return self.db.inc_credits(user_id)

    def dec_credits(self, user_id):
        return self.db.dec_credits(user_id)

    def credits_available(self, user_id):
        return self.get_credits(user_id) > 0

    async def get_places_in_area(self, params, places_type, point_info, adjacent_lon,
                                 adjacent_lat):
        """
        Get the places in the area corresponding to given point.

        :param params: JSON object holding the arguments passed to the endpoint
        from the frontend.
        :param point_info: Object holding the characteristic of the point to
        identify it on the virtually splitted map of the world (zone, subzone,
        etc.).
        :param adjacent_lon: Longitude of the adjacent area.
        :param adjacent_lat: Latitude of the adjacent area.

        :return: The area id used.
        """
        # If those are valid x/y, it means we are looking for an adjacent
        # area to the one containing the original point.
        if adjacent_lon != -1 and adjacent_lat != -1:
            point_info = utm.get_area(adjacent_lat, adjacent_lon)

        # Check subzone exists
        if not self.subzone_exists(point_info.subzone_lon, point_info.subzone_lat):
            subzone_id = self.add_subzone_in_zone(point_info.subzone_lon,
                                                  point_info.subzone_lat,
                                                  point_info.zone,
                                                  point_info.band)

        area_id = self.get_area_id(point_info.subzone_lon, point_info.subzone_lat,
                                   point_info.area_x, point_info.area_y)
        subz_id, area_x, area_y, area_covered = self.get_area_by_id(area_id)
        subzone_lon, subzone_lat = self.db.get_subzone_by_id(subz_id)
        center_lon = subzone_lon + ((area_x + 0.5) * AREA_WIDTH)
        center_lat = subzone_lat + ((area_y + 0.5) * AREA_HEIGHT)
        point_info.set_center(center_lon, center_lat)
        #print(f"DEBUG: POINT INFO")
        #print(f"DEBUG: subzone_lon = {point_info.subzone_lon}, subzone_lat = {point_info.subzone_lat}")
        #print(f"DEBUG: area_x = {point_info.area_x}, area_y = {point_info.area_y}")
        #print(f"DEBUG: area id = {area_id}")
        #print(f"DEBUG: area_x = {area_x}, area_width = {AREA_WIDTH}")
        #print(f"DEBUG: area_y = {area_y}, area_height = {AREA_HEIGHT}")
        #print(f"DEBUG: subzone_id = {subz_id}, subzone_lon = {subzone_lon}, subzone_lat = {subzone_lat}")
        #print(f"DEBUG: center_lon = {center_lon}, center_lat = {center_lat}")

        # Request external API if necessary
        if self.is_area_covered(area_id, places_type):
            print("DEBUG: no request to make")
        else:
            print("DEBUG: requesting external API to get places...")
            new_places = await self.get_places_external(params, center_lon,
                                                        center_lat, AREA_WIDTH,
                                                        AREA_HEIGHT)
            print(f"[+] Adding {len(new_places)} places in area_id {area_id}")
            self.add_places(new_places, places_type, area_id)

        return area_id

    async def get_places(self, request_params, expansion_level=1):
        """
        Get all the places for the area containing the point formed by
        'longitude' and 'latitude'. Bypass the limitation of 20 places imposed
        by the Google Places API by splitting an area in 4 squares recursively
        until we get all of them.

        :param longitude: Longitude of the point where the user is.
        :param latitude: Latitude of the point where the user is.
        :param expansion_level: The number of rounds arounds the given area we
        need to get the places for. Depends on the radius we want to cover.

        :return: A list of places.
        """
        # Parameters for the request to the external service (i.e. Places API)
        params = RequestBody(
            includedTypes = request_params.includedTypes,
            rankPreference = request_params.rankPreference,
            locationRestriction = request_params.locationRestriction,
        )
        places_type = request_params.placesType

        center = params.locationRestriction.circle.center
        area_id = -1
        area_ids = []

        # Find the area in which the point belongs to
        point_info = utm.get_area(center.latitude, center.longitude)

        # Get places for that area
        area_id = await self.get_places_in_area(params, places_type, point_info, -1, -1)
        area_ids.append(area_id)

        # Get places in surronding areas. Depends on the radius we want to
        # cover. Width of an area is approximately 1km but it may vary depending
        # of the region.
        # TODO: either consider 1 expansion level = 1km, or compute something
        #       more precise (expansion level = radius we want / radius area)
        for i in range(1, expansion_level + 1):
            # Above
            print(f"\n[!] Above, level = {i}")
            for j in range(-i, i + 1):
                adjacent_lon = point_info.area_center_lon + AREA_WIDTH * j
                adjacent_lat = point_info.area_center_lat + AREA_HEIGHT * i
                area_id = await self.get_places_in_area(params, places_type,
                                                        point_info,
                                                        adjacent_lon,
                                                        adjacent_lat)
                area_ids.append(area_id)

            # Below
            print(f"\n[!] Below, level = {i}")
            for j in range(-i, i + 1):
                adjacent_lon = point_info.area_center_lon + AREA_WIDTH * j
                adjacent_lat = point_info.area_center_lat - AREA_HEIGHT * i
                area_id = await self.get_places_in_area(params, places_type,
                                                        point_info,
                                                        adjacent_lon,
                                                        adjacent_lat)
                area_ids.append(area_id)

            # Left side
            print(f"\n[!] Left side, level = {i}")
            for j in range(-i + 1, i):
                adjacent_lon = point_info.area_center_lon - AREA_WIDTH * i
                adjacent_lat = point_info.area_center_lat + AREA_HEIGHT * j
                area_id = await self.get_places_in_area(params, places_type,
                                                        point_info,
                                                        adjacent_lon,
                                                        adjacent_lat)
                area_ids.append(area_id)

            # Right side
            print(f"\n[!] Right side, level = {i}")
            for j in range(-i + 1, i):
                adjacent_lon = point_info.area_center_lon + AREA_WIDTH * i
                adjacent_lat = point_info.area_center_lat + AREA_HEIGHT * j
                area_id = await self.get_places_in_area(params, places_type,
                                                        point_info,
                                                        adjacent_lon,
                                                        adjacent_lat)
                area_ids.append(area_id)

        print(f"DEBUG: area_id = {area_id}")
        print(f"DEBUG: area_ids = {area_ids}")
        new_places = self.get_places_from_db(area_ids, params.includedTypes)
        if (new_places == None):
            new_places = []
        else:
            print(f"[+] get_places, len(new_places) = {len(new_places)}")

        return new_places

    async def get_places_external(self, params, center_lon, center_lat, width, height):
        """
        Get places from an external API.
        """
        places = []

        diff_width_km = utm.longitude_diff_to_km(center_lat, center_lon-width/2,
                                          center_lon+width/2)
        diff_height_km = utm.latitude_diff_to_km(center_lat-height/2,
                                          center_lat+height/2, center_lon)
        radius = max(diff_width_km, diff_height_km)
        print(f"[+] Getting places from point ({center_lon}, {center_lat}), radius = {radius}")

        new_center = Circle(
            center = Location(latitude=center_lat, longitude=center_lon),
            radius = round(radius, 1) * 1000 # km to meters
        )
        params.locationRestriction.circle = new_center

        #tmp = await self.get_places_gapi(params)
        tmp = await self.get_places_oapi(params)

        # We reached the limit of results for the API. It is very likely that
        # the area contain more places. Split it in four squares and request
        # again. Mandatory if using the Places API, however pretty much useless
        # when using the Overpass API (50k...).
        if len(tmp) == RESULTS_LIMIT_OAPI:
            # Square (0, 0)
            new_lon, new_lat = self.split_area(center_lon, center_lat, width/2, height/2, 0, 0)
            places += await self.get_places_external(params, new_lon, new_lat,
                                          width/2, height/2)

            # Square (0, 1)
            new_lon, new_lat = self.split_area(center_lon, center_lat, width/2, height/2, 0, 1)
            places += await self.get_places_external(params, new_lon, new_lat,
                                          width/2, height/2)

            # Square (1, 0)
            new_lon, new_lat = self.split_area(center_lon, center_lat, width/2, height/2, 1, 0)
            places += await self.get_places_external(params, new_lon, new_lat,
                                          width/2, height/2)

            # Square (1, 1)
            new_lon, new_lat = self.split_area(center_lon, center_lat, width/2, height/2, 1, 1)
            places += await self.get_places_external(params, new_lon, new_lat,
                                          width/2, height/2)

        else:
            places += tmp

        return places

    def split_area(self, lon, lat, width, height, square_x, square_y):
        new_lon = 0
        new_lat = 0

        if square_x == 0:
            new_lon = lon - width
        elif square_x == 1:
            new_lon = lon + width

        if square_y == 0:
            new_lat = lat - height
        elif square_y == 1:
            new_lat = lat + height

        return new_lon, new_lat

    def get_places_dev_static(self):
        f = open("experiments/example.json", "r", encoding="utf-8")
        data = json.load(f)
        return data["places"]

    async def get_places_gapi(self, params: RequestBody):
        url = "https://places.googleapis.com/v1/places:searchNearby"
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": API_KEY_GPLACES,
            "X-Goog-FieldMask": (
                "places.displayName,places.formattedAddress,places.googleMapsUri,places.location,"
                "places.primaryType,places.currentOpeningHours,places.currentSecondaryOpeningHours,"
                "places.nationalPhoneNumber,places.regularOpeningHours,places.regularSecondaryOpeningHours,places.websiteUri"
            ),
        }
        data = {}

        async with httpx.AsyncClient() as client:
            response = await client.post(url, json=params.dict(), headers=headers)

        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=response.text)

        if response.json() == "{}":
            print("[-] get_places_gapi, nothing returned...")
        else:
            try:
                data = response.json()['places']
                #data = json.dumps(data, ensure_ascii=False)
            except KeyError:
                print(response.json())

        return data

    async def get_places_oapi(self, params: RequestBodyOAPI):
        url = "https://overpass-api.de/api/interpreter"
        radius = int(params.locationRestriction.circle.radius)
        lat = params.locationRestriction.circle.center.latitude
        lon = params.locationRestriction.circle.center.longitude
        amenities = '|'.join(params.includedTypes)
        places = {}

        # Overpass query to get places around the given latitude/longitude with opening_hours
        overpass_query = f"""
        [out:json];
        node
          [amenity~"{amenities}"]
          (around:{radius},{lat},{lon});
        out body;
        """

        async with httpx.AsyncClient() as client:
            response = await client.get(url, params={'data': overpass_query})

        if response.status_code != 200:
            raise HTTPException(status_code=response.status_code, detail=response.text)

        # Parse the JSON response
        data = response.json()
        if data == "{}":
            print("[-] get_places_oapi, nothing returned...")
            return
        places = data.get('elements', [])

        return places
