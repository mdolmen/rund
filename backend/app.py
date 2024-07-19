import requests
import json

from fastapi import FastAPI, Body
from fastapi.encoders import jsonable_encoder
from fastapi.responses import Response
from pydantic import BaseModel

API_KEY_GPLACES = ""
API_KEY_GEOCODE = "";

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

app = FastAPI()

@app.get("/")
async def index():
    return {"message": "ping ok"}

@app.post("/get-places")
async def get_places(body: RequestBody):
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
    response = requests.post(url, json=body.dict(), headers=headers)

    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    data = response.json()['places']
    data = json.dumps(data, ensure_ascii=False)

    return Response(content=data, media_type="application/json")

@app.post("/get-places-dev")
async def get_places_dev(body: RequestBody):
    f = open("example.json", "r", encoding="utf-8")
    data = json.load(f)
    data = json.dumps(data["places"], ensure_ascii=False)
    return Response(content=data, media_type="application/json")

@app.post("/reverse-geocode")
async def reverse_geocode(location: Location):
    url = "https://geocode.maps.co/reverse"
    params = {
        'lat': location.latitude,
        'lon': location.longitude,
        'api_key': API_KEY_GEOCODE
    }

    response = requests.get(url, params=params)

    if response.status_code == 200:
        return response.json()
    else:
        raise HTTPException(status_code=response.status_code, detail="Failed to reverse geocode")
