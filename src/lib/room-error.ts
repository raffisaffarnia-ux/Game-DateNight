/** Only intentional product messages cross the database/UI boundary. */
export function roomError(error: unknown) {
  const message =
    error && typeof error === "object" && "message" in error
      ? String(error.message)
      : "";
  if (message.startsWith("Rooms are not connected yet.")) return message;
  if (message.startsWith("This room already has two people."))
    return "This room already has two people. Ask your partner for a new invitation.";
  if (message.startsWith("That invitation was not found"))
    return "That invitation was not found or has expired. Check the code with your partner.";
  if (message.startsWith("You already have five active rooms."))
    return "You already have five active rooms. Use an existing invitation or try again tomorrow.";
  if (message.startsWith("This room could not be restored.")) return message;
  return "Could not connect to your room. Check your connection and try again.";
}
