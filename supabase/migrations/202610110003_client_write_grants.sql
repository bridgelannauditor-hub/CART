-- Client grants omitted from the initial migration.
-- RLS policies continue to restrict profile edits to the signed-in owner and
-- review writes to the signed-in customer with a delivered order item.

grant update (first_name, last_name, email, phone, shop_name, cover_image,
  profile_image, is_live, notification_preferences)
on public.profiles to authenticated;

grant insert (product_id, customer_id, rating, comment, customer_first_name,
  customer_last_name)
on public.reviews to authenticated;

grant update (rating, comment, customer_first_name, customer_last_name)
on public.reviews to authenticated;
