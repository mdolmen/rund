import requests
import json

from places import Places, RequestBody, AutourRequest, Location

from fastapi import FastAPI, Body, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import Response

API_KEY_GEOCODE = "";

places = Places()

app = FastAPI()

@app.get("/")
async def index():
    return {"message": "ping ok"}

@app.post("/get-places")
async def get_places(params: AutourRequest):
    new_places = await places.get_places(params)

    return new_places

@app.post("/get-places-dev")
async def get_places_dev(params: RequestBody):
    f = open("experiments/example.json", "r", encoding="utf-8")
    data = json.load(f)
    data = json.dumps(data["places"], ensure_ascii=False)
    data = data["places"]
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
