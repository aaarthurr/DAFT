import os
import subprocess
from typing import List
from prompt_toolkit import print_formatted_text, HTML
from google import genai
from google.genai import types

# --- 1. TOOLS DEFINITION ---

def read_file(filename: str) -> str:
    """Read the contents of a specific file to get more context."""
    try:
        with open(filename, "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"

def exec_command(command: str) -> str:
    """Execute a shell command and return the output."""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout if result.stdout else result.stderr
    except Exception as e:
        return f"Error executing command: {e}"

def ask_user(question: str) -> str:
    """Use this to ask the user for more information or clarification."""
    print_formatted_text(HTML(f"<b><ansiyellow>DAFT asks:</ansiyellow></b> {question}"))
    return input("Answer: ")

def deliver_answer(explanation: str, commands: List[str]):
    """Final output tool to provide an explanation and shell commands."""
    pass

# --- 2. IMPROVED SYSTEM RULES ---
system_rules = (
    "### ROLE\n"
    "You are DAFT (Dynamic Assistant for Terminal), a professional-grade Bash shell expert "
    "integrated directly into the user's terminal. You specialize in automation, "
    "system administration, and troubleshooting.\n\n"
    
    "### OPERATIONAL TOOLS\n"
    "1. `read_file(filename)`: Read file contents (scripts, logs, configs). Use this "
    "to understand the current state of the user's code or system configuration.\n"
    "2. `exec_command(command)`: Execute a non-interactive shell command to gather facts "
    "(e.g., check installed versions, directory structures, or hardware info). "
    "Use this to verify assumptions before suggesting a final answer.\n"
    "3. `ask_user(question)`: Ask the user for clarification or missing requirements. "
    "Use this ONLY if the answer cannot be found via `ls` or `read_file`.\n"
    "4. `deliver_answer(explanation, commands)`: Your TERMINAL action. "
    "You MUST use this to provide your final solution. Calling this ends the loop.\n\n"
    
    "### STRICT CONSTRAINTS\n"
    "- COMMUNICATION: Never respond with plain text. Every response must be a tool call.\n"
    "- PROACTIVITY: If information is missing, use `exec_command` or `read_file` to "
    "find it yourself. Do not rely on the user for data you can discover via the shell.\n"
    "- SAFETY: Avoid destructive commands (e.g., `rm -rf /`) unless the user explicitly "
    "requested a deletion. Prefer robust, idempotent commands.\n"
    "- EXPLANATION: In `deliver_answer`, the explanation must be professional and "
    "justify WHY each command is necessary. Keep it scannable and avoid fluff.\n"
    "- FINALITY: You must finish every task by calling `deliver_answer`.\n\n"
    
    "### WORKFLOW\n"
    "1. ANALYZE the user's request.\n"
    "2. PROBE: Use `exec_command` or `read_file` to gather context about the environment.\n"
    "3. REASON: Based on the facts gathered, determine the most efficient commands.\n"
    "4. DELIVER: Call `deliver_answer` with the final explanation and command list."
)


# --- 3. UPDATED ASK FUNCTION ---
def ask(prompt, flags):
    client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"))

    # Register all 4 tools
    config = types.GenerateContentConfig(
        system_instruction=system_rules,
        tools=[read_file, exec_command, ask_user, deliver_answer],
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True)
    )

    try:
        chat = client.chats.create(model="gemini-2.5-flash-lite", config=config)
        response = chat.send_message(prompt)
        
        while True:
            # Safely check for candidates
            if not response.candidates: break
            part = response.candidates[0].content.parts[0]

            if part.function_call:
                call = part.function_call
                
                # --- CASE A: Final Answer ---
                if call.name == 'deliver_answer':
                    explanation = call.args.get('explanation', "Done.")
                    commands = call.args.get('commands', [])
                    
                    print_formatted_text(HTML(f'\n<b><u><ansired>DAFT:</ansired></u></b>'))
                    print(explanation)
                    
                    for cmd in commands:
                        print_formatted_text(HTML(f'<b><ansicyan>BASH &gt; {cmd}</ansicyan></b>'))
                        if input("Execute? [Y/n]: ").upper() == "Y":
                            os.system(cmd)
                    break 

                # --- CASE B: Ask User (No permission needed) ---
                elif call.name == 'ask_user':
                    user_resp = ask_user(call.args['question'])
                    response = chat.send_message(
                        types.Part.from_function_response(name='ask_user', response={'result': user_resp})
                    )

                # --- CASE C: System Tools (Permission needed) ---
                else:
                    out = None
                    
                    if call.name == 'read_file':
                        target = call.args.get('filename', 'unknown')
                        print_formatted_text(HTML(
                            f"<b><ansiyellow>DAFT:</ansiyellow></b> Wants to call <u>read_file</u>\n"
                            f"<b><ansicyan>FILE:</ansicyan></b> <code>{target}</code>\n"
                            f"Allow? [Y/n]"
                        ))
                        if input().upper() == 'Y':
                            out = read_file(target)

                    elif call.name == 'exec_command':
                        cmd = call.args.get('command', 'unknown')
                        print_formatted_text(HTML(
                            f"<b><ansiyellow>DAFT:</ansiyellow></b> Wants to call <u>exec_command</u>\n"
                            f"<b><ansicyan>COMMAND:</ansicyan></b> <code>{cmd}</code>\n"
                            f"Allow? [Y/n]"
                        ))
                        if input().upper() == 'Y':
                            out = exec_command(cmd)

                    # Send the result back if allowed, otherwise send a denial message
                    if out is not None:
                        response = chat.send_message(
                            types.Part.from_function_response(name=call.name, response={'result': out})
                        )
                    else:
                        # If the user said 'n', we MUST tell the AI so it can try something else or stop
                        response = chat.send_message("User denied permission for this specific tool call.")
            else:
                # Catch-all for accidental plain text
                if part.text: print(part.text)
                break

    except Exception as e:
        print(f"DAFT AI Error: {e}")

    return 0