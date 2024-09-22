import json
import utm
import requests
import httpx
import asyncio
import builtins

from pydantic import BaseModel

from db import Database

API_KEY_GPLACES = ""
SUBZONE_SPLIT_X = 64

class Location(BaseModel):
    latitude: float
    longitude: float

class Circle(BaseModel):
    center: Location
    radius: float

class LocationRestriction(BaseModel):
    circle: Circle

class RequestBody(BaseModel):
    includedTypes: list[str]
    rankPreference: str
    locationRestriction: LocationRestriction

class Places:
    def __init__(self):
        self.db = Database()

    def subzone_exists(self, longitude, latitude, number, band):
        return self.db.get_subzone(longitude, latitude)

    def add_subzone_in_zone(self, longitude, latitude, number, band):
        print("DEBUG: add_subzone_in_zone")
        zone_id = self.db.insert_zone(number, band)
        if zone_id == 0:
            return
        print(f"DEBUG: zone_id = {zone_id}")

        subzone_id = self.db.insert_subzone(longitude, latitude, zone_id)
        if subzone_id == 0:
            return
        print(f"DEBUG: subzone_id = {subzone_id}")
        return subzone_id

    def add_place(self, place, area_id):
        formatted_address = place.get("formattedAddress", "Unknown")
        google_maps_uri = place.get("googleMapsUri", "Unknown")
        primary_type = place.get("primaryType", "Unknown")
        display_name_tmp = place.get("displayName", "Unknown")
        display_name = display_name_tmp.get("text", "Unknown")
        longitude = place["location"]["longitude"]
        latitude = place["location"]["latitude"]
        current_opening_hours = place.get("currentOpeningHours", "Unknown")
        current_opening_hours = json.dumps(current_opening_hours, ensure_ascii=False)
        country_id = self.db.get_country(place["formattedAddress"].split(" ")[-1])

        print(f"DEBUG: formatted address = {place["formattedAddress"]}")

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

    def add_places(self, places, area_id):
        print(f"DEBUG: adding places in area {area_id}")

        for place in places:
            self.add_place(place, area_id)

        self.db.set_area_covered(area_id, True)

    def get_places_from_db(self, area_id):
        return self.db.get_places(area_id)

    def get_area(self, row, col):
        return self.db.get_area(row, col)

    def get_area_by_id(self, area_id):
        return self.db.get_area_by_id(area_id)

    def get_area_id(self, row, col):
        return self.db.get_area_id(row, col)

    def is_area_covered(self, area_id):
        return self.db.get_area_covered(area_id)

    def create_area_covered_entries(self, subzone_id, row, col, width, height):
        self.db.insert_area_covered(subzone_id, row, col, width, height)

    async def get_places(self, params, expansion_level=1):
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
        center = params.locationRestriction.circle.center
        area_id = -1

        # Find the area in which the point belongs to
        zone, band, subzone_x, subzone_y, area_row, area_col, area_width, area_height = utm.get_area(
            center.latitude, center.longitude
        )

        # If the subzone has not been seen yet (no request has been made in that
        # region), add it in the db first
        if not self.subzone_exists(subzone_x, subzone_y, zone, band):
            subzone_id = self.add_subzone_in_zone(subzone_x, subzone_y, zone, band)
            self.create_area_covered_entries(subzone_id, area_row, area_col, area_width,
                                    area_height)

        # Get the area id of the area containing the point
        area_id = self.get_area_id(area_row, area_col)
        print(f"DEBUG: area id = {area_id}")

        # Request external API if necessary
        if self.is_area_covered(area_id):
            print("DEBUG: no request to make, getting places from db...")
        else:
            print("DEBUG: requesting external API to get places...")
            subz_id, area_row, area_col, area_width, area_height, area_covered = self.get_area_by_id(area_id)
            subzone_lon, subzone_lat = self.db.get_subzone_by_id(subz_id)
            center_lon = subzone_lon + ((area_row + 0.5) * area_width)
            center_lat = subzone_lat + ((area_col + 0.5) * area_height)
            print(f"DEBUG: area_row = {area_row}, area_width = {area_width}")
            print(f"DEBUG: area_col = {area_col}, area_height = {area_height}")
            print(f"DEBUG: subzone_id = {subz_id}, subzone_lon = {subzone_lon}, subzone_lat = {subzone_lat}")
            print(f"DEBUG: center_lon = {center_lon}, center_lat = {center_lat}")
            new_places = await self.get_places_external(params, center_lon, center_lat, area_width, area_height)
            print(f"DEBUG: adding {len(new_places)}")
            self.add_places(new_places, area_id)

        new_places = self.get_places_from_db(area_id)
        #print(new_places)

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
        print(f"getting places from point ({center_lon}, {center_lat}), radius = {radius}")

        new_center = Circle(
            center = Location(latitude=center_lat, longitude=center_lon),
            radius = round(radius, 1) * 1000 # km to meters
        )
        params.locationRestriction.circle = new_center

        tmp = await self.get_places_gapi(params)

        # We reached the limit of the Google Places API. It is very likely that
        # the area contain more places. Split it in four squares and request
        # again.
        if len(tmp) == 20:
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

        # DEBUG
        for p in places:
            print(p["formattedAddress"])

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
