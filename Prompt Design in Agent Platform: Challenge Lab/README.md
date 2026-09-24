# 🎮 Prompt Design in Agent Platform: Challenge Lab

<h2 align="center">🔥 SOLUTION BY imasis 🔥</h2>

<br>

<br>

### <img src="https://raw.githubusercontent.com/github/explore/main/topics/youtube/youtube.png" width="25" height="25" valign="middle"> Youtube - https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG

### <img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" width="25" height="25" valign="middle"> Github work - https://github.com/CloudRik

<br>

## ⚡ STEP-BY-STEP SOLUTION
<br>




## TASK-1 PROMPT:

```bash


Analyze this image of a Cymbal Direct product. Generate:

1. A short, descriptive text inspired by the image.
2. Catchy phrases suitable for advertisements.
3. A poetic description for a nature-focused campaign.


```

<br>

## TASK-2 PROMPT:

> SYStem Instruction Prompt :


```bash


Cymbal Direct is partnering with an outdoor gear retailer. They're launching a new line of products designed to encourage young
 people to explore the outdoors. Help them create catchy taglines for this product line.

```

<br>

<br>

> Main Box Prompt :


```bash


Generate catchy taglines for Cymbal Direct's new outdoor product line.

Follow these examples:

Input: Write a tagline for a durable backpack designed for hikers that makes them feel prepared. Consider styles like minimalist.
Output: Built for the Journey: Your Adventure Essentials.

Now create taglines that can be customized based on:
- Product attributes (e.g., durable, lightweight, weatherproof)
- Target audience (e.g., young adventurers, families, outdoor enthusiasts)
- Emotional resonance (e.g., empowered, connected, free)

Generate 5 taglines with these parameters.


```
<br>

## TASK-3 PROMPT:

```bash


from google import genai
from google.genai import types

def generate():
    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)
    
    with open('cymbal_product_image.png', 'rb') as f:
        image_bytes = f.read()
    
    response = client.models.generate_content(
        model='gemini-3.5-flash',
        contents=[
            types.Part.from_bytes(
                data=image_bytes,
                mime_type='image/png'
            ),
            "Describe the image colors in 10 words with creative flair."
        ],
        config=types.GenerateContentConfig(
            temperature=1.0,
            max_output_tokens=200,
        )
    )
    print(response.text)

generate()



```

<br>


## TASK-4 -> Follow video instruction:


<br>


<br>

### <img src="https://raw.githubusercontent.com/github/explore/main/topics/youtube/youtube.png" width="25" height="25" valign="middle"> Youtube - https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG

### <img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" width="25" height="25" valign="middle"> Github work - https://github.com/CloudRik

<br>


