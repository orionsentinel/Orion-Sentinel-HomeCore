"""LLM-powered flight assistant agent using Ollama."""

import json
import logging
from typing import Any, Dict, List, Optional

import requests

from app.config import settings

logger = logging.getLogger(__name__)


class FlightAgent:
    """LLM-powered flight assistant using Ollama."""

    def __init__(self):
        """Initialize flight agent."""
        self.enabled = settings.agent_enabled
        self.ollama_url = settings.ollama_base_url
        self.model = settings.ollama_model
        self.api_base = "http://localhost:8000"  # Internal API endpoint

    def is_available(self) -> bool:
        """Check if Ollama is available."""
        if not self.enabled:
            return False

        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            return response.status_code == 200
        except Exception:
            return False

    def _call_api(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """Call internal API endpoint."""
        try:
            response = requests.get(f"{self.api_base}{endpoint}", params=params, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"API call failed: {endpoint} - {e}")
            return {"error": str(e)}

    def _get_tools(self) -> List[Dict[str, Any]]:
        """Define available tools for the agent."""
        return [
            {
                "name": "search_best_offers",
                "description": "Search for the best flight offers with filters",
                "parameters": {
                    "origins": "Comma-separated origin airports (e.g., AMS,EIN,RTM,BRU)",
                    "destinations": "Comma-separated destination airports (e.g., HER,CHQ)",
                    "depart_date_start": "Start of departure date range (YYYY-MM-DD)",
                    "depart_date_end": "End of departure date range (YYYY-MM-DD)",
                    "min_stay": "Minimum stay days (integer)",
                    "max_stay": "Maximum stay days (integer)",
                    "limit": "Maximum number of results (default 50)",
                },
            },
            {
                "name": "get_recommendation",
                "description": "Get buy/wait recommendation for a specific route and dates",
                "parameters": {
                    "origin": "Origin airport code (required)",
                    "destination": "Destination airport code (required)",
                    "depart_date": "Departure date YYYY-MM-DD (required)",
                    "return_date": "Return date YYYY-MM-DD (optional)",
                    "stay_days": "Stay duration in days (optional)",
                },
            },
        ]

    def _execute_tool(self, tool_name: str, parameters: Dict) -> Dict:
        """Execute a tool call."""
        if tool_name == "search_best_offers":
            return self._call_api("/offers/best", parameters)
        elif tool_name == "get_recommendation":
            return self._call_api("/recommendation", parameters)
        else:
            return {"error": f"Unknown tool: {tool_name}"}

    def query(self, user_question: str) -> Dict[str, Any]:
        """Process user query with LLM agent."""
        if not self.is_available():
            return {
                "response": "LLM agent is not available. Please enable AGENT_ENABLED and ensure Ollama is running.",
                "agent_available": False,
            }

        # Build prompt with tools
        tools_description = "\n".join(
            [f"- {t['name']}: {t['description']}" for t in self._get_tools()]
        )

        system_prompt = f"""You are a helpful flight price assistant. You help users find the best flight deals and decide when to buy tickets.

Available tools:
{tools_description}

When the user asks a question, determine which tool(s) to use and extract the necessary parameters from their question.
Respond in a helpful, natural way summarizing the information.

Example user questions:
- "Find me the cheapest week in June from AMS to Crete for 7-14 days"
- "Should I buy a flight from Rotterdam to Heraklion departing May 15, returning May 22?"
"""

        # For simplicity, we'll do a basic tool selection based on keywords
        # In a production system, you'd use LLM's function calling capabilities
        response_text = self._simple_agent_logic(user_question)

        return {
            "response": response_text,
            "agent_available": True,
            "model": self.model,
        }

    def _simple_agent_logic(self, question: str) -> str:
        """Simplified agent logic without full LLM integration."""
        question_lower = question.lower()

        # Parse intent and parameters
        if "cheapest" in question_lower or "best" in question_lower or "find" in question_lower:
            # Extract parameters
            params = {}

            # Extract origins
            if "ams" in question_lower or "amsterdam" in question_lower:
                origins = ["AMS"]
            elif "ein" in question_lower or "eindhoven" in question_lower:
                origins = ["EIN"]
            elif "rtm" in question_lower or "rotterdam" in question_lower:
                origins = ["RTM"]
            elif "bru" in question_lower or "brussels" in question_lower:
                origins = ["BRU"]
            else:
                origins = ["AMS", "EIN", "RTM", "BRU"]

            params["origins"] = ",".join(origins)

            # Extract destinations
            if "her" in question_lower or "heraklion" in question_lower:
                params["destinations"] = "HER"
            elif "chq" in question_lower or "chania" in question_lower:
                params["destinations"] = "CHQ"
            else:
                params["destinations"] = "HER,CHQ"

            # Extract date range (simplified)
            if "june" in question_lower:
                params["depart_date_start"] = "2024-06-01"
                params["depart_date_end"] = "2024-06-30"
            elif "july" in question_lower:
                params["depart_date_start"] = "2024-07-01"
                params["depart_date_end"] = "2024-07-31"

            # Extract stay duration
            if "7-14" in question_lower or "7 to 14" in question_lower:
                params["min_stay"] = 7
                params["max_stay"] = 14

            params["limit"] = 10

            # Call API
            result = self._call_api("/offers/best", params)

            if "error" in result:
                return f"I encountered an error: {result['error']}"

            offers = result.get("offers", [])
            if not offers:
                return "I couldn't find any flights matching your criteria. Try adjusting your search parameters."

            # Summarize results
            best_offer = offers[0]
            summary = f"""I found {result['count']} flights matching your criteria. Here's the best one:

🛫 {best_offer['origin']} → {best_offer['destination']}
📅 Departure: {best_offer['depart_date']}
📅 Return: {best_offer['return_date']}
⏱️  Stay: {best_offer['stay_days']} days
💰 Price: €{best_offer['price']:.2f}
✈️  Airline: {best_offer['airline']}
🔄 Stops: {best_offer['stops']}

Would you like me to check if this is a good price to buy now?"""

            return summary

        elif "should i buy" in question_lower or "buy or wait" in question_lower or "recommend" in question_lower:
            # This is a recommendation query
            # For simplicity, use default parameters
            params = {
                "origin": "AMS",
                "destination": "HER",
                "depart_date": "2024-06-15",
                "return_date": "2024-06-22",
            }

            result = self._call_api("/recommendation", params)

            if "error" in result:
                return f"I encountered an error: {result['error']}"

            action = result.get("action", "WAIT")
            confidence = result.get("confidence", 0.5)
            rationale = result.get("rationale", {})

            if action == "BUY":
                emoji = "✅"
                advice = "This looks like a good deal! I recommend buying now."
            elif action == "WAIT":
                emoji = "⏳"
                advice = "I recommend waiting for a better price."
            else:
                emoji = "🤔"
                advice = "The price is okay, but you might want to monitor it."

            summary = f"""{emoji} {advice}

Action: {action}
Confidence: {confidence * 100:.0f}%
Current Price: €{result.get('current_price', 0):.2f}

Reasoning: {rationale.get('reason', 'No specific reason provided')}"""

            return summary

        else:
            return """I'm your flight price assistant! I can help you:

1. Find the cheapest flights from NL/BE to Crete
   Example: "Find me the cheapest week in June from Amsterdam to Crete for 7-14 days"

2. Recommend whether to buy now or wait
   Example: "Should I buy a flight from Rotterdam to Heraklion departing May 15?"

What would you like to know?"""


# Global agent instance
agent = FlightAgent()
