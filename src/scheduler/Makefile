# Makefile pour le comptage de mots distribué

total.txt: count1.txt count2.txt count3.txt count4.txt count5.txt
	cat count1.txt count2.txt count3.txt count4.txt count5.txt | awk '{sum += $$1} END {print sum}' > total.txt

count1.txt: part1.txt wordcount
	./wordcount part1.txt > count1.txt

count2.txt: part2.txt wordcount
	./wordcount part2.txt > count2.txt

count3.txt: part3.txt wordcount
	./wordcount part3.txt > count3.txt

count4.txt: part4.txt wordcount
	./wordcount part4.txt > count4.txt

count5.txt: part5.txt wordcount
	./wordcount part5.txt > count5.txt

wordcount: wordcount.c
	gcc -o wordcount wordcount.c

clean:
	rm -f count*.txt total.txt wordcount
