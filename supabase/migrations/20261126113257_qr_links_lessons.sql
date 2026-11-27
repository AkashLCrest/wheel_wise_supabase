-- B22: one booklet QR code per Brain De Fogger lesson (lesson1..lesson8).
insert into public.qr_links (code, target, note) values
  ('lesson1', 'BrainDeFogger/1', 'Book: Brain De Fogger lesson 1 (Choose your wheel)'),
  ('lesson2', 'BrainDeFogger/2', 'Book: Brain De Fogger lesson 2 (Find the zero)'),
  ('lesson3', 'BrainDeFogger/3', 'Book: Brain De Fogger lesson 3 (Pick a target)'),
  ('lesson4', 'BrainDeFogger/4', 'Book: Brain De Fogger lesson 4 (Meet the neighbours)'),
  ('lesson5', 'BrainDeFogger/5', 'Book: Brain De Fogger lesson 5 (Tokens and dots)'),
  ('lesson6', 'BrainDeFogger/6', 'Book: Brain De Fogger lesson 6 (Read your range)'),
  ('lesson7', 'BrainDeFogger/7', 'Book: Brain De Fogger lesson 7 (Switch to the table)'),
  ('lesson8', 'BrainDeFogger/8', 'Book: Brain De Fogger lesson 8 (Try another target)')
on conflict (code) do nothing;
