from db import Database

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
