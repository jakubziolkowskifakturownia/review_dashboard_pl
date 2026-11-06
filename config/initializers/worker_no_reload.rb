# Worker jobów w dev nie przeładowuje kodu — nowy kod w workerze to `touch tmp/restart.txt`
# (README). Przeładowanie czeka, aż skończą się WSZYSTKIE trwające joby, a do tego czasu
# blokuje każdy nowy job i heartbeat; przy godzinnej sesji review supervisor uznaje
# workera za martwego i oblewa jego joby, choć sesje Claude dalej pracują.
SolidQueue.on_worker_start { Rails.application.reloader.check = -> { false } } if Rails.env.development?
