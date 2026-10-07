import { z } from "zod";

/** أسماء الأحداث المسموحة — تطابق `Events` في Swift. أي حدث آخر يُرفض. */
export const ALLOWED_EVENTS = new Set([
  "destination_searched", "route_options_shown", "route_option_selected", "navigation_started",
  "reroute_offered", "reroute_accepted", "reroute_dismissed", "trip_completed",
  "nearby_opened", "restaurant_opened", "cafe_opened", "nearby_time_filter_selected",
  "place_sort_selected", "place_opened", "place_saved", "place_navigation_started",
]);

const FORBIDDEN_PARAM_KEYS = /^(lat|lng|latitude|longitude|coord|coordinates|location|email|phone|name|user_id|device_id)$/i;

export const EventsBody = z.object({
  events: z.array(z.object({
    name: z.string().refine((n) => ALLOWED_EVENTS.has(n), "unknown event"),
    params: z.record(z.string().max(32), z.string().max(100)).default({}),
    timestamp: z.string(),
  })).min(1).max(50),
}).superRefine((b, ctx) => {
  for (const e of b.events) {
    for (const k of Object.keys(e.params)) {
      if (FORBIDDEN_PARAM_KEYS.test(k)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `param "${k}" is not allowed (privacy)` });
    }
  }
});

export type EventsPayload = z.infer<typeof EventsBody>;
