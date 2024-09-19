import json

from db import Database

SUBZONE_SPLIT_X = 64

class Places:
    def __init__(self):
        self.db = Database()

    def subzone_exists(self, longitude, latitude, number, band):
        return self.db.get_subzone(longitude, latitude, number, band)

    def add_subzone_in_zone(self, longitude, latitude, number, band):
        print("DEBUG: add_subzone_in_zone")
        zone_id = self.db.insert_zone(number, band)
        if zone_id == 0:
            return
        print(f"DEBUG: zone_id = {zone_id}")


        subzone_id = self.db.insert_subzone(longitude, latitude, zone_id)
        if subzone_id == 0:
            return

        self.db.insert_area_covered(subzone_id)

    def add_place(self, place, area_id, area_x):
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
            area_id,
            area_x
        )

        return

    def add_places(self, places, area_id, area_x, bitmap):
        print(f"DEBUG: adding places in area {area_id}")

        for place in places:
            self.add_place(place, area_id, area_x)

        # update bitmap of covered areas
        self.set_area_bitmap(area_id, area_x, bitmap)

    def get_area_bitmap(self, subzone_x, subzone_y, area_y):
        return self.db.get_area_bitmap(subzone_x, subzone_y, area_y)

    def set_area_bitmap(self, area_id, area_x, bitmap):
        bitmap |= 1 << (SUBZONE_SPLIT_X - 1 - area_x)
        self.db.set_area_bitmap(area_id, bitmap)
