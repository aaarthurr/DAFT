import re
import os

def clean_log_text(text):
    """
    Supprime tous les codes d'échappement ANSI (couleurs, etc.) du log brut.
    (C'est la même fonction qu'avant, on la garde)
    """
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


def get_memory(x_prompts_ago):
    """
    Trouve le log de la session, le nettoie, et renvoie 
    les 'x' derniers blocs de commande/résultat.
    (Version corrigée)
    """
    # 1. Trouve le bon fichier log de la session
    log_file_path = os.environ.get("DAFT_HISTORY_FILE")
    if not log_file_path:
        print("DAFT Error: Logger not active. (DAFT_HISTORY_FILE not set).")
        print("Active log with daft_start_log")
        return None
        
    try:
        # 2. Lit et nettoie le fichier
        with open(log_file_path, 'r') as f:
            raw_text = f.read()
        clean_text = clean_log_text(raw_text)

        # 3. Découpe le log en blocs
        #    CHANGEMENT N°1 : J'ai enlevé le \n pour trouver le TOUT PREMIER prompt
        prompt_regex = r"([a-zA-Z0-9_-]+@[a-zA-Z0-9_-]+:.*[$#] )"
        
        parts = re.split(prompt_regex, clean_text)
        
        full_history = []
        # On regroupe (prompt + son output)
        # On commence à 1, on saute de 2
        for i in range(1, len(parts) - 1, 2):
            prompt_string = parts[i]
            command_and_output = parts[i+1]
            full_history.append(prompt_string + command_and_output)

        # 4. "skip son propre prompt"
        history_to_send = full_history[:-1]
        
        # 5. On prend les 'x' derniers prompts
        final_history_blocks = history_to_send[ -x_prompts_ago: ]
        
        # CHANGEMENT N°2 : On ne joint QUE les blocs sélectionnés.
        # On ne touche plus à parts[0].
        if not final_history_blocks:
             return "DAFT: No history found to analyze."

        final_context = "\n".join(final_history_blocks)
        
        return final_context
        
    except Exception as e:
        print(f"DAFT Error: Could not read or parse log file: {e}")
        return None