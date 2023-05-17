import httpclient, json, strformat, os, terminal, strutils, parseopt, sequtils

proc helpMessage(): string = "Usage: " & getAppFileName().extractFileName() & """ [options]

Options:
  -m, --model MODEL             Select the AI model to use. Options: [default, chatgpt | gpt-3.5-turbo, gpt4 | gpt-4]. Default is "default" which maps to "gpt-3.5-turbo" currently (Will always map to the newest model that is available for all, e.g. not waitlisted). Do not rely upon "default" to always map to gpt-3.5-turbo.
      --chatgpt                 Use the ChatGPT model (alias for --model gpt-3.5-turbo).
      --gpt4                    Use the GPT-4 model (alias for --model gpt-4).
  --key, --apiKey KEY           Use the specified OpenAI API key. Has precedence over --apiEnv and --apiKeyFile.
  --env, --apiEnv ENV           Specify the environment variable name that stores the OpenAI API key. Default is "OPENAI_API_KEY". Has precedence over --apiKeyFile.
  --keyFile, --apiKeyFile FILE  Read the API key from a specified file. Default is "apiKey.txt".
  -h, --help                    Show this help message.

Example:
  """ & getAppFilename().extractFilename() & """ --model gpt-4 --apiKey "sk-xxxxxxxxxxxxxxxxxxxx"

Description:
  This Nim program uses the OpenAI API to interact with the ChatGPT or GPT-4 models. You can specify the model, provide an API key, or specify the environment variable or file that stores the API key. Once the program is running, you can chat with the AI model by typing messages and pressing Enter. The AI will respond with a generated message.
"""

proc main() =
  var args: string = ""
  
  for i in 1..paramCount():
    args &= paramStr(i)
  
  var p = initOptParser(args)
  var model: string = "default"
  var openaiApiKey: string = ""
  var apiFile: string = "apiKey.txt"
  var apiEnv: string = "OPENAI_API_KEY"
  while true:
    p.next()
    case p.kind:
      of cmdEnd: break
      of cmdLongOption, cmdShortOption:
        if p.val != "": # Args with a value
          case p.key.toLowerAscii():
            of "model", "m":
              if model == "default":
                model = p.val.toLowerAscii()
            of "apiKey", "key":
              openaiApiKey = p.val
            of "apiEnv", "env":
              apiEnv = p.val
            of "apiKeyFile", "keyFile":
              apiFile = p.val
            else:
              discard ""
        else: # Value-less args
          case p.key.toLowerAscii():
            of "chatgpt":
              model = "gpt-3.5-turbo"
            of "gpt4":
              model = "gpt-4"
            of "help", "h":
              echo helpMessage()
              quit()
            else:
              discard ""
      of cmdArgument:
        discard ""
  
  if openaiApiKey == "":
    openaiApiKey = getEnv(apiEnv)
    if openaiApiKey == "":
      try:
        openaiApiKey = readFile(apiFile)
      except:
        discard ""
      styledEcho(styleBright, fgMagenta, "\nUnable to find API key. Fixes:\n  - Pass one with --apiKey\n  - Store one in an enviroment variable. Pass the name of the enviroment variable with --apiEnv. The default is OPENAI_API_KEY.\n  - Put the API key in a file and pass the file name with --apiKeyFile. The default is apiKey.txt.\n\nThese methods are checked in this order: --apiKey, then --apiEnv, then --apiFile. Whichever method succeeds first in this list will be used.")
      quit()

  case model.toLowerAscii():
    of "default", "chatgpt":
      model = "gpt-3.5-turbo"
    of "gpt4":
      model = "gpt-4"
    else:
      discard ""

  if not (model in ["gpt-3.5-turbo", "gpt-4"]):
    styledEcho(styleBright, fgMagenta, "\nInvalid model: ", fgRed, model, "\nPlease enter one of: [default, gpt-3.5-turbo")
    quit()
  
  
  if openaiApiKey[0..2] != "sk-":
    styledEcho(styleBright, fgMagenta, "\nInvalid API key.")
    quit()

  var modelString: string
  case model:
    of "gpt-4":
      modelString = "GPT-4"
    of "gpt-3.5-turbo":
      modelString = "ChatGPT"
  
  let url = "https://api.openai.com/v1/chat/completions"
  
  let headers = newHttpHeaders([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " & openaiApiKey)
  ])
  
  type
    ChatRole = enum
      SystemRole = "system", AssistantRole = "assistant", UserRole = "user"
    ChatMessage = object
      role: ChatRole
      content: string
    ChatConversation = seq[ChatMessage]
  
  proc chatComp(messages: ChatConversation, model: string): string =
    let payload = %*{
      "model": model,
      "messages": %*(messages)
    }
    
    let client = newHttpClient()
    client.headers = headers
    
    let response = client.post(url, body = $payload)
    
    let output = parseJson(response.body)
  
    let message = output["choices"][0]["message"]["content"].getStr()
    
    if response.status == Http200:
      return message
    else:
      return "Error: " & response.status
    
    client.close()
  
  var aiAnswer, userInput: string
  var userChar: char
  var conversation: ChatConversation = @[
    ChatMessage(role: SystemRole, content: "You are a helpful assistant.")
  ]
  
  eraseScreen()
  setCursorPos(0, 0)
  
  styledEcho(styleBright, fmt"Welcome to {modelString} (Nim)!")
  echo "\n"
  
  while true:
    stdout.write("You: ")
    userInput = ""
    while true:
      userChar = getch()
      case userChar:
        of '\003':
          styledEcho(styleBright, fgMagenta, "\nProgram quit with ^C\n")
          quit()
        of '\x7f':
          if userInput.len > 0:
            userInput = userInput[0 ..< ^1]
            cursorBackward(1)
            stdout.write(" ")
            cursorBackward(1)
        of '\r':
          if userInput[^1] == '\\':
            userInput &= "\n"
            echo ""
          else:
            echo ""
            break
        else:
          userInput &= $userChar
          stdout.styledWrite(styleBright, fgRed, $userChar)
          
    conversation.add(ChatMessage(role: UserRole, content: userInput))
    styledEcho("\n" & fmt"{modelString}: ", styleBright, fgBlue, "Thinking...")
    
    aiAnswer = conversation.chatComp(model).strip()
    conversation.add(ChatMessage(role: AssistantRole, content: aiAnswer))
    cursorUp(1)
    eraseLine()
    styledEcho(fmt"{modelString}: ", styleBright, fgBlue, aiAnswer)
    echo ""

when isMainModule:
  main()
