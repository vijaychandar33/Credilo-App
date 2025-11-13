# Supabase MCP Setup for Cursor

## What is MCP?

Model Context Protocol (MCP) allows AI assistants in Cursor to directly interact with your Supabase database, making it easier to:
- Query your database
- View table schemas
- Run SQL commands
- Manage your database structure

## Step 1: Generate Supabase Personal Access Token (PAT)

1. **Go to Supabase Dashboard**:
   - Visit [https://supabase.com/dashboard](https://supabase.com/dashboard)
   - Log in to your account

2. **Navigate to Access Tokens**:
   - Click on your **Profile/Avatar** (top right)
   - Go to **Account Settings** → **Access Tokens**
   - Or visit: [https://supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens)

3. **Create New Token**:
   - Click **"Create New Token"**
   - Give it a descriptive name: `Cursor MCP Server`
   - Click **"Generate Token"**
   - **⚠️ IMPORTANT**: Copy the token immediately - you won't be able to see it again!

## Step 2: Configure Cursor MCP Settings

### Option A: Using Cursor Settings UI (Recommended)

1. **Open Cursor Settings**:
   - Press `Cmd + ,` (Mac) or `Ctrl + ,` (Windows/Linux)
   - Or: **Cursor** → **Settings**

2. **Navigate to MCP**:
   - Go to **Features** → **MCP**
   - Or search for "MCP" in settings

3. **Add MCP Server**:
   - Click **"Add MCP Server"** or **"Configure MCP Servers"**
   - Add the Supabase server configuration

### Option B: Manual Configuration File

1. **Find MCP Config Location**:
   
   The MCP config file location depends on your OS:
   
   **macOS**: 
   ```bash
   ~/Library/Application Support/Cursor/User/globalStorage/mcp.json
   ```
   
   **Windows**: 
   ```
   %APPDATA%\Cursor\User\globalStorage\mcp.json
   ```
   
   **Linux**: 
   ```
   ~/.config/Cursor/User/globalStorage/mcp.json
   ```

2. **Create/Edit the Config File**:

   Create or edit the file with this content:

   ```json
   {
     "mcpServers": {
       "supabase": {
         "command": "npx",
         "args": [
           "-y",
           "@supabase/mcp-server-supabase@latest",
           "--access-token",
           "YOUR_PERSONAL_ACCESS_TOKEN_HERE"
         ]
       }
     }
   }
   ```

   **Replace `YOUR_PERSONAL_ACCESS_TOKEN_HERE`** with the token you generated in Step 1.

3. **Alternative: Project-Level Config** (in your project folder):

   Create `.cursor/mcp.json` in your project root:

   ```json
   {
     "mcpServers": {
       "supabase": {
         "command": "npx",
         "args": [
           "-y",
           "@supabase/mcp-server-supabase@latest",
           "--access-token",
           "YOUR_PERSONAL_ACCESS_TOKEN_HERE"
         ]
       }
     }
   }
   ```

## Step 3: Restart Cursor

1. **Quit Cursor completely**:
   - Mac: `Cmd + Q`
   - Windows/Linux: Close all Cursor windows

2. **Reopen Cursor**
3. The MCP server should connect automatically

## Step 4: Verify MCP Connection

1. **Open Cursor Chat/Composer** (Cmd+L or Ctrl+L)
2. **Test with a query**:
   - "Show me my Supabase tables"
   - "What tables exist in my database?"
   - "List all my Supabase projects"

3. **Check MCP Status**:
   - Look for MCP connection indicators in Cursor
   - Check the status bar or MCP settings to see if it's connected

If MCP is working, the AI should be able to query your Supabase account and databases directly.

## Troubleshooting

### MCP Server Not Connecting

1. **Check Node.js is installed**:
   ```bash
   node --version
   npm --version
   ```
   If not installed, download from [nodejs.org](https://nodejs.org/)

2. **Test MCP server manually**:
   ```bash
   npx -y @supabase/mcp-server-supabase@latest --access-token YOUR_TOKEN
   ```

3. **Check Cursor logs**:
   - **Mac**: `Cmd + Shift + P` → "Developer: Toggle Developer Tools"
   - **Windows/Linux**: `Ctrl + Shift + P` → "Developer: Toggle Developer Tools"
   - Look in the Console tab for MCP-related errors

4. **Verify token**:
   - Make sure your Personal Access Token is correct
   - Check that the token hasn't expired
   - Regenerate if needed

5. **Check config file location**:
   - Verify the MCP config file is in the correct location
   - Ensure JSON syntax is valid (use a JSON validator)

### Common Issues

**"Command not found" or "npx not found"**:
- Install Node.js: [nodejs.org](https://nodejs.org/)
- Restart terminal/IDE after installation

**"Invalid token" or "Authentication failed"**:
- Regenerate your Personal Access Token
- Make sure you copied the entire token
- Check for extra spaces or line breaks

**MCP shows as disconnected**:
- Restart Cursor completely
- Check if npx can run: `npx --version`
- Try the manual test command above

## What You Can Do With MCP

Once connected, you can ask the AI to:

- **Query data**: "Show me all cash expenses from today"
- **View schemas**: "What's the structure of the cash_expenses table?"
- **Run SQL**: "Count how many branches I have"
- **Check data**: "What's the total sales for this month?"
- **Debug issues**: "Why is my query failing?"

## Security Notes

⚠️ **Important**:
- **Personal Access Tokens** have access to your Supabase account - keep them secret!
- Never commit tokens to version control (add `.cursor/mcp.json` to `.gitignore` if using project-level config)
- Use project-level config (`.cursor/mcp.json`) for team projects, but keep tokens in environment variables
- You can revoke tokens anytime from Supabase dashboard → Account Settings → Access Tokens
- The MCP server operates in **read-only mode by default** for safety

## Next Steps

After setting up MCP, you can:
1. Ask the AI to help debug database queries
2. Get help with SQL operations
3. Automatically generate database queries for your Flutter app
4. Monitor your database structure and data

