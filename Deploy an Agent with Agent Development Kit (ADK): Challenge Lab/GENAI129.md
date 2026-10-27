<h1 align="center">🎮 Deploy an Agent with Agent Development Kit (ADK): Challenge Lab</h1>

<h2 align="center">🔥 SOLUTION BY IMASIS 🔥</h2>

<br>

<h3>🌐 Connect With Me</h3>

- <img src="https://raw.githubusercontent.com/github/explore/main/topics/youtube/youtube.png" width="25" height="25" valign="middle"> **YouTube** — [@imasis-k8x](https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG)
- <img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" width="25" height="25" valign="middle"> **GitHub** — [CloudRik](https://github.com/CloudRik)
- <img src="https://github.com/user-attachments/assets/8c66fd5e-8d52-4803-b085-0f0273988fee" width="25" height="25" valign="middle"> **Arcade Points** — [arcadesuite.pages.dev](https://arcadesuite.pages.dev/)

<br>

---

## ⚡ STEP-BY-STEP SOLUTION

<br>

### 🔹 TASK - 1

#### > Follow the Video



<br>

---

### 🔹 TASK- 2 - Run Your Lab Instructions's Command Not This Command So Follow The Video

#### Step -1 : Download and install the files.

```bash
gcloud storage cp -r gs://qwiklabs-gcp-04-a44854c34629-bucket/adk_challenge_lab .
export PATH=$PATH:"/home/${USER}/.local/bin"
python3 -m pip install chainlit==2.11.1
python3 -m pip install -r adk_challenge_lab/requirements.txt

```
#### STEP -2 : Copy Print Search's ID

Agent Platform > Agents > Search 

Then Copy - **Print Search** ID


#### STEP -3 : Create an `.env` file (insert your ID here)

```bash
cd ~/adk_challenge_lab
cat << EOF > .env
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=qwiklabs-gcp-04-a44854c34629
GOOGLE_CLOUD_LOCATION=us-central1
RESOURCES_BUCKET=qwiklabs-gcp-04-a44854c34629-bucket
MODEL=gemini-2.5-flash
SEARCH_ENGINE_ID=YOUR_ID
EOF
```
#### STEP -4 : copy the `.env` file to the agent folder

```bash

cp .env paint_agent/.env
```

<br>

---

### 🔹 TASK- 3 
<br>

#### 3.1 — Check the error (it’s noted in the optional Boot Lab)

```bash
adk run paint_agent
```

When [user] arrives, type `hello`
> If the agent follows up asking if you'd like to learn more about Cymbal Shops' paints, reply: `Yes`

Ten Type `exit` and Enter.

<br>

#### 3.2 — Open The File


```bash

nano paint_agent/agent.py
```

#### 3.3 — Edit It : Find The Line - sub_agents=[

```bash
sub_agents=[room_planner_agent],
tools=[
        AgentTool(agent=search_agent),
        set_session_value,
    ],
```

✅ Save it

- Ctrl + O  (save)

- Enter 

- Ctrl + X  (exit)


<br>


#### 3.4 — Test it

```bash
adk run paint_agent
```
- [user]: Type `hello`

- He will ask about the paint -> type `Yes`

- Type `exit` to leave.

  <br>

> And Then Run This Command

```bash
sed -i 's/tool_context.state\[key\] = value/tool_context.state[key] = value\n    return f"stored {value} in {key}"/' paint_agent/tools.py
```
<br>


### 🔹 TASK- 4 Run This Command or Follow The Video

```bash
adk web --allow_origins "regex:https://.*\.cloudshell\.dev"
```
<br>

### 🔹 TASK- 5

```bash
cd ~/adk_challenge_lab
adk deploy agent_engine --display_name "Paint Agent" ./paint_agent
```
<br>

### 🔹 TASK- 6 : 

<br>

#### Step - 6.1 :Check The Resources Name Using This Command

```bash
python3 -c "import vertexai; from vertexai.preview import reasoning_engines; vertexai.init(project='[ENTER_YOUR_PROJECT_ID]', location='us-central1'); engines = reasoning_engines.ReasoningEngine.list(); [print(e.resource_name) for e in engines]"
```

<br>

#### Step - 6.2 : Run This Command

```bash
cd ~/adk_challenge_lab
nano chainlit_ui/app.py
```

<br>

#### Step - 6.3 : Find This Line 

`agent = client.agent_engines.get(name='YOUR_AGENT_RESOURCE_NAME')`

> Then Paste The Resources Name

- Ctrl + O  (save)

- Enter 

- Ctrl + X  (exit)

<br>


 #### Step - 6.4 : Run it (open in browser)

```bash
 cd ~/adk_challenge_lab/chainlit_ui
chainlit run app.py

```


<br>

 #### Step - 6.5 :Chat (Final Test)


1. `hello` **(Enter)**

2. `yes` **(Enter)**

3. `I'd like to use Forever Paint` **(Enter)**

4. `Two rooms. The living room and a baby's room.` **(Enter)**

5. `"Sunlight through a canvas tent" for the baby's room and "Coffee Cream" for the living room.` **(Enter)**

6. `The living room is 5m by 4m. 2.5m high. 1 door, 3 windows.` **(Enter)**

7. `Two coats.` (Enter)

8. `The baby's room is 3m by 3m. 2.5m high. 1 door, 1 window.` **(Enter)**

9. `Always two coats.` **(Enter)**

<br>








<div align="center">

### ⭐ Star this repo if it helped you!

<img src="https://raw.githubusercontent.com/github/explore/main/topics/youtube/youtube.png" width="25" height="25" valign="middle"> **YouTube** — https://youtube.com/@imasis-k8x?si=lO3ixe-KbnN1nNBG

<img src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" width="25" height="25" valign="middle"> **GitHub** — https://github.com/CloudRik

</div>
