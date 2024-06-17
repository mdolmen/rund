import requests
import json

from fastapi import FastAPI, UploadFile, Request, Form

app = FastAPI()

@app.get("/")
async def index():
    return {"message": "ping ok"}

@app.get("/get-places")
async def get_places():
    f = open("example.json")
    return json.load(f)
