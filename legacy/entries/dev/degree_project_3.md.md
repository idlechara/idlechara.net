[//]: # (Tue Jan 8 19:22:38 -03 2019)
# Degree project pt. 3 - Metric space indexing explained (WIP)

This post will cover the fundamentals on how metric spaces actually work

## A bit of jokes

Before going into indexing and similarity search, let's dive a bit onto the notion of [distance](https://en.wikipedia.org/wiki/Distance). According
to wikipedia, the term "Distance" is a numerical measurement of how far apart objects are. As it, we can say that it is pretty much a human concept.
Whilst for animals the concept of "distance" is something that they actually use everyday, we humans have used this concept to reflect a bunch of
things into reality.

One of such concepts is similarity, which is defined how "distant" an object is closer to another in terms of its caracteristics. For example, we say that two cats are similar animals because both are mammals but if you ask your neighbour if your cat is similar to yours then he/she will probably say: "You're wrong, my cat is different than yours.". Obviously, because as your neighbour sees other "qualities" on his/her cat, there are no cat like his/her own.

But if you're grumpy and you say "Your cat is as grumpy as me" will probably agree with you, as you're comparing only one feature from the entire set of features of your cat.

So, distance and similarity concepts are quite ambiguous and depends heavily on whom you ask or the context on which word is used.

## Similarity between two elements and how to reflect that into a database
Let's say now that we have a list of cats as follows


| id |breed       | hair color            | size (cm) | eye color   |
|:---|:----------:|:---------------------:|:---------:|------------:|
|1   | calico     | brown, yellow, white  | 130       | brown       |
|2   | calico     | brown, yellow, white  | 120       | brown       |
|3   | shorthair  | black, white          | 134       | blue        |
|4   | shorthair  | black, grey, white    | 102       | blue, brown |
|5   | persian    | orange                | 112       | blue        |
|6   | tonkinese  | black                 | 150       | brown       |

Then, it's clear that cats 1 and 2 are the most similar but it's because they do share similar traits. But in terms of size, the cats 1 and 3 are the most similar in betweenn, since they have only 4 centimeters of difference in between.

So, how do you ask for the most 2 similar cat in terms of size?

```sql
SELECT * FROM cats ORDER BY size
```
If you identify a cat and then find the most closer to it (index ±1) then you were to identify the cats closer to it.

But well, you need to order the entire database in order to do that. It's easy on this table since it has only 6 elements but imagine working on billions of cats. That will simply won't work, as this operation is O(n).

Another way of doing this is as follows:
```sql
-- assuming that cat_size, and cat_id is our target
SELECT * from cats WHERE size >= cat_size AND id IS NOT cat_id ORDER BY size LIMIT(1)
-- assuming that cat_size, and cat_id is our target
SELECT * from cats WHERE size <= cat_size AND id IS NOT cat_id ORDER BY size LIMIT(1)
```

And this will return the most "similar" cat in terms of size, which could be one of the two performed queries, still being O(n).

If we were to simplify this query, then we should compute the differennce between cat sizes for all cats regarding to a single one and then, query over that value, but doing so will involve O(n) on computing the differences and will only work on one cat. If we were to solve this in a faster way, then in a naive way we should compute this value for all cats and waste O(n^2) space.
