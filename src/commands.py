import os
import subprocess
import re
from prompt_toolkit import print_formatted_text, HTML
from google import genai
from google.genai import types

# --- SYSTEM RULES ---
system_rules = (
    "You are DAFT, an integrated assistant for a Bash shell."
    "Your goal is to be helpful, accurate, and concise."
    "When you suggest a shell command, write it between ```bash ... ```."
    "Keep answers as short as possible, but **accuracy is more important than brevity**."
    "Avoid unnecessary explanations."
    "You can use the 'read_file' tool to get more context if the user's file list or memory is not enough."
    "You can use the 'exec_command' tool to run shell commands and get their output."
)

# --- DEFINE TOOLS ---
def read_file(filename: str) -> str:
    """
    Read the contents of a specific file to get more context.
    """
    try:
        with open(filename, "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"

def exec_command(command: str) -> str:
    """
    Execute a shell command and return the output.
    """
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return result.stdout
    except Exception as e:
        return f"Error executing command: {e}"

# --- HANDLE RESPONSE ---
def handle_response(text):
    suggested_command = []
    pattern = r"```(?:bash|sh|shell)?\n(.*?)```"
    parts = re.split(pattern, text, flags=re.DOTALL)
    
    print_formatted_text(HTML(
        f'<b><u><ansired>DAFT:</ansired></u></b>'
    ))

    for i, part in enumerate(parts):
        part = part.strip()
        if not part: continue
        if i % 2 == 1:
            command_to_run = part
            suggested_command.append(command_to_run)
            print_formatted_text(HTML(f'<b><ansicyan>BASH:</ansicyan></b>'))
            for line in command_to_run.split('\n'):
                print_formatted_text(HTML(f'<b><ansicyan>&gt; {line}</ansicyan></b>'))
        else:
            print(part)
    return suggested_command

# --- ASK FUNCTION ---
def ask(prompt, flags):
    from utils import get_memory # Local import to avoid circular dependency issues

    if len(prompt.strip()) == 0:
        print("DAFT: Please provide a question to ask.")
        return "Please provide a question to ask."
        
    if len(prompt) > 150:
        print("DAFT: Your question is too long. Please limit it to 150 characters.")
        return "Your question is too long. Please limit it to 150 characters."
    
    mem_prompt = ""
    list_prompt = ""

    # --- Memory Logic ---
    memory = get_memory(flags.memory) 
    if memory:
        if len(memory) > 1000:
            print(f"Warning: The memory context is large ({len(memory)} characters).")
            big_mem_input = input("Keep All(K) / Keep 1000 last characters(L) / Dont keep any(N) ? ").upper()
            if big_mem_input == "K":
                mem_prompt = f"Here is some context from the current shell session:\n{memory}\n"
            elif big_mem_input == "L":
                mem_prompt = f"Here is some context from the current shell session:\n{memory[-1000:]}\n"
            elif big_mem_input == "N":
                mem_prompt = ""
            else:
                print("Invalid input. Skipping memory.")
        else :
            mem_prompt = f"Here is some context from the current shell session:\n{memory}\n"

    # --- List Flag Logic ---
    if flags.list:
        try:
            files = subprocess.run(["ls", "-l", "-a"], capture_output=True, text=True, check=True)
            pwd = subprocess.run(["pwd"], capture_output=True, text=True, check=True)
            list_prompt = f"The current directory is:\n{pwd.stdout}\nThe files in that directory are:\n{files.stdout}\n"
        except Exception as e:
            print(f"DAFT: Error getting file list: {e}")

    # --- Build Final Prompt ---
    final_prompt = prompt
    if mem_prompt or list_prompt:
        final_prompt = mem_prompt + "\n" + list_prompt + f"\nBased on this context, answer the following question concisely:\n{prompt}"

    # --- NEW SDK SETUP ---
    # 1. Initialize Client
    client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"))

    # 2. Create Chat with Config (Tools & System Instructions go here now)
    chat_session = client.chats.create(
        model="gemini-2.5-flash",
        config=types.GenerateContentConfig(
            system_instruction=system_rules,
            tools=[read_file, exec_command], # The SDK automatically converts these functions to tools
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True) # We handle this manually for safety
        )
    )

    proposed = [] 
    try:
        # --- FIRST CALL ---
        response = chat_session.send_message(final_prompt)
        
        # --- AGENT LOOP ---
        while True:
            # Get the first candidate's content part
            # Note: In the new SDK, structure is slightly different but attributes are similar.
            # We access the first candidate's first part.
            if not response.candidates:
                print("DAFT: No response from AI.")
                break
                
            response_part = response.candidates[0].content.parts[0]

            # Check for Function Call
            if response_part.function_call:
                function_call = response_part.function_call
                
                if function_call.name == 'read_file':
                    filename = function_call.args['filename']
                    print_formatted_text(HTML(f"<b><ansiyellow>DAFT:</ansiyellow></b> Asked to read <b>{filename}</b>. Allow? [Y/n]"))
                    choice = input().upper()
                    
                    if choice == 'Y':
                        try:
                            file_content = read_file(filename) 
                            # Send tool response back
                            response = chat_session.send_message(
                                types.Part.from_function_response(
                                    name='read_file',
                                    response={'content': file_content}
                                )
                            )
                        except Exception as e:
                            response = chat_session.send_message(
                                types.Part.from_function_response(
                                    name='read_file',
                                    response={'error': str(e)}
                                )
                            )
                    else:
                        response = chat_session.send_message("User denied permission.")

                elif function_call.name == 'exec_command':
                    command = function_call.args['command']

                    dangerous_keywords = ["rm ", "mv ", "dd ", "> /dev", "mkfs", ":(){ :|:& };:"]
                    is_dangerous = any(bad in command for bad in dangerous_keywords)
                    
                    # 2. Display with appropriate warning color
                    if is_dangerous:
                        print_formatted_text(HTML(f"<b><ansired>WARNING: DANGEROUS COMMAND DETECTED</ansired></b>"))
                        print_formatted_text(HTML(f"<b><ansiyellow>DAFT:</ansiyellow></b> Wants to run: <b>{command}</b>"))
                    else:
                        print_formatted_text(HTML(f"<b><ansiyellow>DAFT:</ansiyellow></b> Wants to run: <b>{command}</b>"))


                    print_formatted_text(HTML(f"<b><ansiyellow>DAFT:</ansiyellow></b> Asked to execute <b>{command}</b>. Allow? [Y/n]"))
                    choice = input().upper()
                    
                    if choice == 'Y':
                        try:
                            cmd_output = exec_command(command) 
                            response = chat_session.send_message(
                                types.Part.from_function_response(
                                    name='exec_command',
                                    response={'output': cmd_output}
                                )
                            )
                        except Exception as e:
                            response = chat_session.send_message(
                                types.Part.from_function_response(
                                    name='exec_command',
                                    response={'error': str(e)}
                                )
                            )
                    else:
                        response = chat_session.send_message("User denied permission.")
                
            elif response_part.text:
                # Text response (Final answer)
                proposed = handle_response(response_part.text) 
                break 
            
            else:
                print("DAFT: AI returned an unexpected response type.")
                break

    except Exception as e:
        print(f"DAFT AI Error: {e}")
    
    # --- Execute Proposed Commands ---
    for command in proposed:
        print("-----------------------------------------------------")
        print("DAFT proposed this command:" + command)
        if (input("do you want to execute it [Y/n] :").upper() == "Y"):
            os.system(command) 
        else:
            print("Skipping...")
    return 0