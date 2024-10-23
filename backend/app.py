import requests
import json

from places import Places, RequestBody, AutourRequest, Location

from fastapi import FastAPI, Body, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.responses import Response
from pydantic import BaseModel

API_KEY_GEOCODE = "";

places = Places()

app = FastAPI()

class VerifyPurchaseRequest(BaseModel):
    verificationData: str
    platform: str
    productId: str
    userId: str

class UserIdRequest(BaseModel):
    userId: str

@app.get("/")
async def index():
    return {"message": "ping ok"}

@app.post("/get-places")
async def get_places(params: AutourRequest):
    if places.credits_available(params.userId):
        new_places = await places.get_places(params)
        places.dec_credits(params.userId)
    else:
        print("[-] Not enough credits...")
        new_places = []

    # TODO: return a more complex object with an error in case not enough
    # credits
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

@app.post("/get-credits")
async def get_credits(request: UserIdRequest):
    return {"credits": places.get_credits(request.userId)}

@app.post("/verify-purchase")
async def verify_purchase(purchase: VerifyPurchaseRequest):
    """
    Endpoint to verify iOS in-app purchase using App Store Server API
    """
    # Apple's sandbox or production URL
    APPLE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt"
    APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt"

    # DEBUG
    user_credits = handle_payment_success('test.credits.20', purchase.userId)

    #payload = {
    #    'receipt-data': purchase.verificationData,
    #    'password': 'YOUR_SHARED_SECRET' # TODO
    #}

    #try:
    #    response = requests.post(APPLE_PRODUCTION_URL, json=payload)
    #    result = response.json()

    #    # If status is 21007, the receipt is from the sandbox environment, resend to the sandbox server
    #    if result.get("status") == 21007:
    #        response = requests.post(APPLE_SANDBOX_URL, json=payload)
    #        result = response.json()

    #    # Handle the response
    #    if result.get("status") == 0:
    #        # Successful verification
    #        receipt = result.get('receipt')
    #        product_receipts = [item for item in receipt['in_app'] if
    #                            item['productId'] == purchase.productId]
    #        if not product_receipts:
    #            raise HTTPException(status_code=400,
    #                                detail="[-] Product not found in receipt.")

    #        user_credits = handle_payment_success(
    #            product_receipts['in_app'][0]['productId'],
    #            purchase.userId
    #        )
    #        data = json.dumps({"status": "success", "credits_available": user_credits})
    #        return Response(content=data, media_type="application/json")

    #    else:
    #        # Verification failed
    #        raise HTTPException(status_code=400,
    #                            detail=f"Verification failed with status: {result.get('status')}")

    #except Exception as e:
    #    raise HTTPException(status_code=500, detail=str(e))

    data = json.dumps({"status": "success", "credits_available": user_credits})

    return Response(content=data, media_type="application/json")

def handle_payment_success(product_id, user_id):
    print("DEBUG: handle_payment_success")
    print(f"DEBUG: user id = {user_id}")
    quantity = {
        'test.credits.20': 20,
        'test.credits.50': 50,
        'test.credits.200': 200
    }
    print(f"DEBUG: product id = {product_id}")
    credits = quantity[product_id]

    places.insert_purchase(user_id, credits)

    places.insert_credits(user_id, credits)

    user_credits = places.get_credits(user_id)
    print(f"user credits = {user_credits}")

    return user_credits
