import requests
import json

from fastapi import FastAPI, Body
from fastapi.encoders import jsonable_encoder
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI()

class PlaceRequest(BaseModel):
    address: str

@app.get("/")
async def index():
    return {"message": "ping ok"}

@app.post("/get-places")
async def get_places(req: PlaceRequest):
    print(f"address = {req.address}")
    f = open("example-few-data.json", "r", encoding="utf-8")
    data = json.load(f)
    data = json.dumps(data["places"], ensure_ascii=False)
    return Response(content=data, media_type="application/json")
