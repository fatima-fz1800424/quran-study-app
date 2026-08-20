# Retrieval label review

Top 10 results per query from the production retrieval path
(`all-mpnet-base-v2`, dense). Generated for relabelling - see
`docs/DECISIONS.md` for why the existing labels are suspect.

How to annotate: for each query, list the result numbers that are genuinely
relevant, e.g. `query 3: results 1, 4, 7`. A result already in
`expected_refs` is marked **[labelled]**; one that is not is marked
`[unlabelled]`. A relevant result marked `[unlabelled]` is a label gap -
it is currently scored as a miss.

Two queries are deliberate negatives with no expected refs: nothing should
be relevant. They are included so that can be confirmed rather than assumed.

---

## Query 1: patience in hardship

Currently labelled relevant: `16:127`, `2:45`, `94:5`, `94:6`

1. **2:45** (score 0.528) **[labelled]**
   > Nay, seek (Allah's) help with patient perseverance and prayer: It is indeed hard, except to those who bring a lowly spirit,-

2. **21:83** (score 0.495) `[unlabelled]`
   > And (remember) Job, when He cried to his Lord, "Truly distress has seized me, but Thou art the Most Merciful of those that are merciful."

3. **94:5** (score 0.484) **[labelled]**
   > So, verily, with every difficulty, there is relief:

4. **94:6** (score 0.484) **[labelled]**
   > Verily, with every difficulty there is relief.

5. **70:5** (score 0.477) `[unlabelled]`
   > Therefore do thou hold Patience,- a Patience of beautiful (contentment).

6. **41:35** (score 0.459) `[unlabelled]`
   > And no one will be granted such goodness except those who exercise patience and self-restraint,- none but persons of the greatest good fortune.

7. **18:67** (score 0.449) `[unlabelled]`
   > (The other) said: "Verily thou wilt not be able to have patience with me!"

8. **30:60** (score 0.446) `[unlabelled]`
   > So patiently persevere: for verily the promise of Allah is true: nor let those shake thy firmness, who have (themselves) no certainty of faith.

9. **10:11** (score 0.445) `[unlabelled]`
   > If Allah were to hasten for men the ill (they have earned) as they would fain hasten on the good,- then would their respite be settled at once. But We leave those who rest not their hope on their meeting with Us, in their trespasses, wandering in distraction to and fro.

10. **2:214** (score 0.443) `[unlabelled]`
   > Or do ye think that ye shall enter the Garden (of bliss) without such (trials) as came to those who passed away before you? they encountered suffering and adversity, and were so shaken in spirit that even the Messenger and those of faith who were with him cried: "When (will come) the help of Allah?" Ah! Verily, the help of Allah is (always) near!

Labelled but not retrieved in the top 10: `16:127`

---

## Query 2: what does the Quran say about orphans

Currently labelled relevant: `4:2`, `4:6`, `4:8`, `89:17`

1. **2:220** (score 0.712) `[unlabelled]`
   > (Their bearings) on this life and the Hereafter. They ask thee concerning orphans. Say: "The best thing to do is what is for their good; if ye mix their affairs with yours, they are your brethren; but Allah knows the man who means mischief from the man who means good. And if Allah had wished, He could have put you into difficulties: He is indeed Exalted in Power, Wise."

2. **4:127** (score 0.683) `[unlabelled]`
   > They ask thy instruction concerning the women say: Allah doth instruct you about them: And (remember) what hath been rehearsed unto you in the Book, concerning the orphans of women to whom ye give not the portions prescribed, and yet whom ye desire to marry, as also concerning the children who are weak and oppressed: that ye stand firm for justice to orphans. There is not a good deed which ye do, but Allah is well-acquainted therewith.

3. **6:152** (score 0.663) `[unlabelled]`
   > And come not nigh to the orphan's property, except to improve it, until he attain the age of full strength; give measure and weight with (full) justice;- no burden do We place on any soul, but that which it can bear;- whenever ye speak, speak justly, even if a near relative is concerned; and fulfil the covenant of Allah: thus doth He command you, that ye may remember.

4. **4:6** (score 0.605) **[labelled]**
   > Make trial of orphans until they reach the age of marriage; if then ye find sound judgment in them, release their property to them; but consume it not wastefully, nor in haste against their growing up. If the guardian is well-off, Let him claim no remuneration, but if he is poor, let him have for himself what is just and reasonable. When ye release their property to them, take witnesses in their presence: But all-sufficient is Allah in taking account.

5. **4:2** (score 0.602) **[labelled]**
   > To orphans restore their property (When they reach their age), nor substitute (your) worthless things for (their) good ones; and devour not their substance (by mixing it up) with your own. For this is indeed a great sin.

6. **89:17** (score 0.594) **[labelled]**
   > Nay, nay! but ye honour not the orphans!

7. **93:9** (score 0.590) `[unlabelled]`
   > Therefore, treat not the orphan with harshness,

8. **93:6** (score 0.581) `[unlabelled]`
   > Did He not find thee an orphan and give thee shelter (and care)?

9. **21:26** (score 0.569) `[unlabelled]`
   > And they say: "(Allah) Most Gracious has begotten offspring." Glory to Him! they are (but) servants raised to honour.

10. **4:3** (score 0.564) `[unlabelled]`
   > If ye fear that ye shall not be able to deal justly with the orphans, Marry women of your choice, Two or three or four; but if ye fear that ye shall not be able to deal justly (with them), then only one, or (a captive) that your right hands possess, that will be more suitable, to prevent you from doing injustice.

Labelled but not retrieved in the top 10: `4:8`

---

## Query 3: charity and giving to the poor

Currently labelled relevant: `2:215`, `2:271`, `2:273`

1. **41:7** (score 0.571) `[unlabelled]`
   > Those who practise not regular Charity, and who even deny the Hereafter.

2. **23:4** (score 0.569) `[unlabelled]`
   > Who are active in deeds of charity;

3. **30:38** (score 0.548) `[unlabelled]`
   > So give what is due to kindred, the needy, and the wayfarer. That is best for those who seek the Countenance, of Allah, and it is they who will prosper.

4. **2:215** (score 0.536) **[labelled]**
   > They ask thee what they should spend (In charity). Say: Whatever ye spend that is good, is for parents and kindred and orphans and those in want and for wayfarers. And whatever ye do that is good, -Allah knoweth it well.

5. **107:3** (score 0.533) `[unlabelled]`
   > And encourages not the feeding of the indigent.

6. **2:273** (score 0.500) **[labelled]**
   > (Charity is) for those in need, who, in Allah's cause are restricted (from travel), and cannot move about in the land, seeking (For trade or work): the ignorant man thinks, because of their modesty, that they are free from want. Thou shalt know them by their (Unfailing) mark: They beg not importunately from all the sundry. And whatever of good ye give, be assured Allah knoweth it well.

7. **107:7** (score 0.497) `[unlabelled]`
   > But refuse (to supply) (even) neighbourly needs.

8. **2:271** (score 0.486) **[labelled]**
   > If ye disclose (acts of) charity, even so it is well, but if ye conceal them, and make them reach those (really) in need, that is best for you: It will remove from you some of your (stains of) evil. And Allah is well acquainted with what ye do.

9. **30:39** (score 0.482) `[unlabelled]`
   > That which ye lay out for increase through the property of (other) people, will have no increase with Allah: but that which ye lay out for charity, seeking the Countenance of Allah, (will increase): it is these who will get a recompense multiplied.

10. **90:14** (score 0.470) `[unlabelled]`
   > Or the giving of food in a day of privation

---

## Query 4: the story of Moses and Pharaoh

Currently labelled relevant: `28:3`, `28:4`

1. **28:3** (score 0.678) **[labelled]**
   > We rehearse to thee some of the story of Moses and Pharaoh in Truth, for people who believe.

2. **89:10** (score 0.672) `[unlabelled]`
   > And with Pharaoh, lord of stakes?

3. **28:8** (score 0.652) `[unlabelled]`
   > Then the people of Pharaoh picked him up (from the river): (It was intended) that (Moses) should be to them an adversary and a cause of sorrow: for Pharaoh and Haman and (all) their hosts were men of sin.

4. **28:4** (score 0.635) **[labelled]**
   > Truly Pharaoh elated himself in the land and broke up its people into sections, depressing a small group among them: their sons he slew, but he kept alive their females: for he was indeed a maker of mischief.

5. **28:38** (score 0.629) `[unlabelled]`
   > Pharaoh said: "O Chiefs! no god do I know for you but myself: therefore, O Haman! light me a (kiln to bake bricks) out of clay, and build me a lofty palace, that I may mount up to the god of Moses: but as far as I am concerned, I think (Moses) is a liar!"

6. **2:49** (score 0.616) `[unlabelled]`
   > And remember, We delivered you from the people of Pharaoh: They set you hard tasks and punishments, slaughtered your sons and let your women-folk live; therein was a tremendous trial from your Lord.

7. **10:83** (score 0.612) `[unlabelled]`
   > But none believed in Moses except some children of his people, because of the fear of Pharaoh and his chiefs, lest they should persecute them; and certainly Pharaoh was mighty on the earth and one who transgressed all bounds.

8. **40:26** (score 0.599) `[unlabelled]`
   > Said Pharaoh: "Leave me to slay Moses; and let him call on his Lord! What I fear is lest he should change your religion, or lest he should cause mischief to appear in the land!"

9. **26:16** (score 0.599) `[unlabelled]`
   > "So go forth, both of you, to Pharaoh, and say: 'We have been sent by the Lord and Cherisher of the worlds;

10. **20:49** (score 0.599) `[unlabelled]`
   > (When this message was delivered), (Pharaoh) said: "Who, then, O Moses, is the Lord of you two?"

---

## Query 5: how should I treat my parents

Currently labelled relevant: `17:23`, `17:24`, `29:8`, `31:14`

1. **17:23** (score 0.493) **[labelled]**
   > Thy Lord hath decreed that ye worship none but Him, and that ye be kind to parents. Whether one or both of them attain old age in thy life, say not to them a word of contempt, nor repel them, but address them in terms of honour.

2. **3:159** (score 0.457) `[unlabelled]`
   > It is part of the Mercy of Allah that thou dost deal gently with them Wert thou severe or harsh-hearted, they would have broken away from about thee: so pass over (Their faults), and ask for (Allah's) forgiveness for them; and consult them in affairs (of moment). Then, when thou hast Taken a decision put thy trust in Allah. For Allah loves those who put their trust (in Him).

3. **29:8** (score 0.457) **[labelled]**
   > We have enjoined on man kindness to parents: but if they (either of them) strive (to force) thee to join with Me (in worship) anything of which thou hast no knowledge, obey them not. Ye have (all) to return to me, and I will tell you (the truth) of all that ye did.

4. **2:220** (score 0.365) `[unlabelled]`
   > (Their bearings) on this life and the Hereafter. They ask thee concerning orphans. Say: "The best thing to do is what is for their good; if ye mix their affairs with yours, they are your brethren; but Allah knows the man who means mischief from the man who means good. And if Allah had wished, He could have put you into difficulties: He is indeed Exalted in Power, Wise."

5. **17:24** (score 0.350) **[labelled]**
   > And, out of kindness, lower to them the wing of humility, and say: "My Lord! bestow on them thy Mercy even as they cherished me in childhood."

6. **4:11** (score 0.345) `[unlabelled]`
   > Allah (thus) directs you as regards your Children's (Inheritance): to the male, a portion equal to that of two females: if only daughters, two or more, their share is two-thirds of the inheritance; if only one, her share is a half. For parents, a sixth share of the inheritance to each, if the deceased left children; if no children, and the parents are the (only) heirs, the mother has a third; if the deceased Left brothers (or sisters) the mother has a sixth. (The distribution in all cases ('s) after the payment of legacies and debts. Ye know not whether your parents or your children are nearest to you in benefit. These are settled portions ordained by Allah; and Allah is All-knowing, Al-wise.

7. **9:94** (score 0.343) `[unlabelled]`
   > They will present their excuses to you when ye return to them. Say thou: "Present no excuses: we shall not believe you: Allah hath already informed us of the true state of matters concerning you: It is your actions that Allah and His Messenger will observe: in the end will ye be brought back to Him Who knoweth what is hidden and what is open: then will He show you the truth of all that ye did."

8. **31:14** (score 0.331) **[labelled]**
   > And We have enjoined on man (to be good) to his parents: in travail upon travail did his mother bear him, and in years twain was his weaning: (hear the command), "Show gratitude to Me and to thy parents: to Me is (thy final) Goal.

9. **4:22** (score 0.305) `[unlabelled]`
   > And marry not women whom your fathers married,- except what is past: It was shameful and odious,- an abominable custom indeed.

10. **64:15** (score 0.300) `[unlabelled]`
   > Your riches and your children may be but a trial: but in the Presence of Allah, is the highest, Reward.

---

## Query 6: what does the Quran say about anxiety

Currently labelled relevant: `16:127`, `2:45`, `94:5`, `94:6`

1. **20:113** (score 0.559) `[unlabelled]`
   > Thus have We sent this down - an arabic Qur'an - and explained therein in detail some of the warnings, in order that they may fear Allah, or that it may cause their remembrance (of Him).

2. **12:86** (score 0.539) `[unlabelled]`
   > He said: "I only complain of my distraction and anguish to Allah, and I know from Allah that which ye know not...

3. **6:17** (score 0.530) `[unlabelled]`
   > "If Allah touch thee with affliction, none can remove it but He; if He touch thee with happiness, He hath power over all things.

4. **11:33** (score 0.520) `[unlabelled]`
   > He said: "Truly, Allah will bring it on you if He wills,- and then, ye will not be able to frustrate it!

5. **10:62** (score 0.512) `[unlabelled]`
   > Behold! verily on the friends of Allah there is no fear, nor shall they grieve;

6. **2:2** (score 0.512) `[unlabelled]`
   > This is the Book; in it is guidance sure, without doubt, to those who fear Allah;

7. **20:3** (score 0.507) `[unlabelled]`
   > But only as an admonition to those who fear (Allah),-

8. **26:142** (score 0.506) `[unlabelled]`
   > Behold, their brother Salih said to them: "Will you not fear (Allah)?

9. **6:51** (score 0.504) `[unlabelled]`
   > Give this warning to those in whose (hearts) is the fear that they will be brought (to judgment) before their Lord: except for Him they will have no protector nor intercessor: that they may guard (against evil).

10. **26:177** (score 0.501) `[unlabelled]`
   > Behold, Shu'aib said to them: "Will ye not fear (Allah)?

Labelled but not retrieved in the top 10: `16:127`, `2:45`, `94:5`, `94:6`

---

## Query 7: what does the Quran say about depression

Currently labelled relevant: `2:153`, `65:3`, `94:5`, `94:6`

1. **12:86** (score 0.526) `[unlabelled]`
   > He said: "I only complain of my distraction and anguish to Allah, and I know from Allah that which ye know not...

2. **6:17** (score 0.500) `[unlabelled]`
   > "If Allah touch thee with affliction, none can remove it but He; if He touch thee with happiness, He hath power over all things.

3. **21:83** (score 0.492) `[unlabelled]`
   > And (remember) Job, when He cried to his Lord, "Truly distress has seized me, but Thou art the Most Merciful of those that are merciful."

4. **26:3** (score 0.484) `[unlabelled]`
   > It may be thou frettest thy soul with grief, that they do not become Believers.

5. **10:11** (score 0.471) `[unlabelled]`
   > If Allah were to hasten for men the ill (they have earned) as they would fain hasten on the good,- then would their respite be settled at once. But We leave those who rest not their hope on their meeting with Us, in their trespasses, wandering in distraction to and fro.

6. **10:107** (score 0.456) `[unlabelled]`
   > If Allah do touch thee with hurt, there is none can remove it but He: if He do design some benefit for thee, there is none can keep back His favour: He causeth it to reach whomsoever of His servants He pleaseth. And He is the Oft-Forgiving, Most Merciful.

7. **12:95** (score 0.452) `[unlabelled]`
   > They said: "By Allah! truly thou art in thine old wandering mind."

8. **6:33** (score 0.451) `[unlabelled]`
   > We know indeed the grief which their words do cause thee: It is not thee they reject: it is the signs of Allah, which the wicked contemn.

9. **2:286** (score 0.451) `[unlabelled]`
   > On no soul doth Allah Place a burden greater than it can bear. It gets every good that it earns, and it suffers every ill that it earns. (Pray:) "Our Lord! Condemn us not if we forget or fall into error; our Lord! Lay not on us a burden Like that which Thou didst lay on those before us; Our Lord! Lay not on us a burden greater than we have strength to bear. Blot out our sins, and grant us forgiveness. Have mercy on us. Thou art our Protector; Help us against those who stand against faith."

10. **3:178** (score 0.445) `[unlabelled]`
   > Let not the Unbelievers think that our respite to them is good for themselves: We grant them respite that they may grow in their iniquity: But they will have a shameful punishment.

Labelled but not retrieved in the top 10: `2:153`, `65:3`, `94:5`, `94:6`

---

## Query 8: what does the Quran say about gratitude

Currently labelled relevant: `14:7`, `16:18`, `2:152`, `31:12`

1. **31:12** (score 0.670) **[labelled]**
   > we bestowed (in the past) Wisdom on Luqman: "Show (thy) gratitude to Allah." Any who is (so) grateful does so to the profit of his own soul: but if any is ungrateful, verily Allah is free of all wants, Worthy of all praise.

2. **76:9** (score 0.588) `[unlabelled]`
   > (Saying),"We feed you for the sake of Allah alone: no reward do we desire from you, nor thanks.

3. **34:4** (score 0.577) `[unlabelled]`
   > That He may reward those who believe and work deeds of righteousness: for such is Forgiveness and a Sustenance Most Generous."

4. **11:90** (score 0.576) `[unlabelled]`
   > "But ask forgiveness of your Lord, and turn unto Him (in repentance): For my Lord is indeed full of mercy and loving-kindness."

5. **14:7** (score 0.571) **[labelled]**
   > And remember! your Lord caused to be declared (publicly): "If ye are grateful, I will add more (favours) unto you; But if ye show ingratitude, truly My punishment is terrible indeed."

6. **26:127** (score 0.558) `[unlabelled]`
   > "No reward do I ask of you for it: my reward is only from the Lord of the Worlds.

7. **26:180** (score 0.558) `[unlabelled]`
   > "No reward do I ask of you for it: my reward is only from the Lord of the Worlds.

8. **26:164** (score 0.558) `[unlabelled]`
   > "No reward do I ask of you for it: my reward is only from the lord of the Worlds.

9. **26:145** (score 0.558) `[unlabelled]`
   > "No reward do I ask of you for it: my reward is only from the Lord of the Worlds.

10. **107:4** (score 0.547) `[unlabelled]`
   > So woe to the worshippers

Labelled but not retrieved in the top 10: `16:18`, `2:152`

---

## Query 9: what does the Quran say about justice

Currently labelled relevant: `16:90`, `4:58`, `5:8`, `6:152`

1. **16:90** (score 0.671) **[labelled]**
   > Allah commands justice, the doing of good, and liberality to kith and kin, and He forbids all shameful deeds, and injustice and rebellion: He instructs you, that ye may receive admonition.

2. **10:44** (score 0.594) `[unlabelled]`
   > Verily Allah will not deal unjustly with man in aught: It is man that wrongs his own soul.

3. **13:6** (score 0.572) `[unlabelled]`
   > They ask thee to hasten on the evil in preference to the good: Yet have come to pass, before them, (many) exemplary punishments! But verily thy Lord is full of forgiveness for mankind for their wrong-doing, and verily thy Lord is (also) strict in punishment.

4. **47:4** (score 0.569) `[unlabelled]`
   > Therefore, when ye meet the Unbelievers (in fight), smite at their necks; At length, when ye have thoroughly subdued them, bind a bond firmly (on them): thereafter (is the time for) either generosity or ransom: Until the war lays down its burdens. Thus (are ye commanded): but if it had been Allah's Will, He could certainly have exacted retribution from them (Himself); but (He lets you fight) in order to test you, some with others. But those who are slain in the Way of Allah,- He will never let their deeds be lost.

5. **40:31** (score 0.559) `[unlabelled]`
   > "Something like the fate of the People of Noah, the 'Ad, and the Thamud, and those who came after them: but Allah never wishes injustice to his Servants.

6. **48:14** (score 0.557) `[unlabelled]`
   > To Allah belongs the dominion of the heavens and the earth: He forgives whom He wills, and He punishes whom He wills: but Allah is Oft-Forgiving, Most Merciful.

7. **5:118** (score 0.556) `[unlabelled]`
   > "If Thou dost punish them, they are Thy servant: If Thou dost forgive them, Thou art the Exalted in power, the Wise."

8. **67:28** (score 0.552) `[unlabelled]`
   > Say: "See ye?- If Allah were to destroy me, and those with me, or if He bestows His Mercy on us,- yet who can deliver the Unbelievers from a grievous Penalty?"

9. **10:52** (score 0.552) `[unlabelled]`
   > "At length will be said to the wrong-doers: 'Taste ye the enduring punishment! ye get but the recompense of what ye earned!'"

10. **55:7** (score 0.539) `[unlabelled]`
   > And the Firmament has He raised high, and He has set up the Balance (of Justice),

Labelled but not retrieved in the top 10: `4:58`, `5:8`, `6:152`

---

## Query 10: what does the Quran say about forgiveness

Currently labelled relevant: `39:53`, `4:110`, `64:14`, `71:10`

1. **45:14** (score 0.718) `[unlabelled]`
   > Tell those who believe, to forgive those who do not look forward to the Days of Allah: It is for Him to recompense (for good or ill) each People according to what they have earned.

2. **40:42** (score 0.716) `[unlabelled]`
   > "Ye do call upon me to blaspheme against Allah, and to join with Him partners of whom I have no knowledge; and I call you to the Exalted in Power, Who forgives again and again!"

3. **71:10** (score 0.696) **[labelled]**
   > "Saying, 'Ask forgiveness from your Lord; for He is Oft-Forgiving;

4. **12:98** (score 0.682) `[unlabelled]`
   > He said: "Soon will I ask my Lord for forgiveness for you: for he is indeed Oft-Forgiving, Most Merciful."

5. **9:27** (score 0.672) `[unlabelled]`
   > Again will Allah, after this, turn (in mercy) to whom He will: for Allah is Oft-forgiving, Most Merciful.

6. **5:118** (score 0.657) `[unlabelled]`
   > "If Thou dost punish them, they are Thy servant: If Thou dost forgive them, Thou art the Exalted in power, the Wise."

7. **20:82** (score 0.656) `[unlabelled]`
   > "But, without doubt, I am (also) He that forgives again and again, to those who repent, believe, and do right, who,- in fine, are ready to receive true guidance."

8. **40:31** (score 0.647) `[unlabelled]`
   > "Something like the fate of the People of Noah, the 'Ad, and the Thamud, and those who came after them: but Allah never wishes injustice to his Servants.

9. **9:68** (score 0.644) `[unlabelled]`
   > Allah hath promised the Hypocrites men and women, and the rejecters, of Faith, the fire of Hell: Therein shall they dwell: Sufficient is it for them: for them is the curse of Allah, and an enduring punishment,-

10. **40:40** (score 0.637) `[unlabelled]`
   > "He that works evil will not be requited but by the like thereof: and he that works a righteous deed - whether man or woman - and is a Believer- such will enter the Garden (of Bliss): Therein will they have abundance without measure.

Labelled but not retrieved in the top 10: `39:53`, `4:110`, `64:14`

---

## Query 11: what does the Quran say about seeking knowledge

Currently labelled relevant: `16:78`, `20:114`, `39:9`, `96:1`

1. **2:32** (score 0.605) `[unlabelled]`
   > They said: "Glory to Thee, of knowledge We have none, save what Thou Hast taught us: In truth it is Thou Who art perfect in knowledge and wisdom."

2. **47:24** (score 0.597) `[unlabelled]`
   > Do they not then earnestly seek to understand the Qur'an, or are their hearts locked up by them?

3. **20:114** (score 0.570) **[labelled]**
   > High above all is Allah, the King, the Truth! Be not in haste with the Qur'an before its revelation to thee is completed, but say, "O my Lord! advance me in knowledge."

4. **47:16** (score 0.564) `[unlabelled]`
   > And among them are men who listen to thee, but in the end, when they go out from thee, they say to those who have received Knowledge, "What is it he said just then?" Such are men whose hearts Allah has sealed, and who follow their own lusts.

5. **28:80** (score 0.556) `[unlabelled]`
   > But those who had been granted (true) knowledge said: "Alas for you! The reward of Allah (in the Hereafter) is best for those who believe and work righteousness: but this none shall attain, save those who steadfastly persevere (in good)."

6. **38:88** (score 0.554) `[unlabelled]`
   > "And ye shall certainly know the truth of it (all) after a while."

7. **42:52** (score 0.550) `[unlabelled]`
   > And thus have We, by Our Command, sent inspiration to thee: thou knewest not (before) what was Revelation, and what was Faith; but We have made the (Qur'an) a Light, wherewith We guide such of Our servants as We will; and verily thou dost guide (men) to the Straight Way,-

8. **31:15** (score 0.537) `[unlabelled]`
   > "But if they strive to make thee join in worship with Me things of which thou hast no knowledge, obey them not; yet bear them company in this life with justice (and consideration), and follow the way of those who turn to me (in love): in the end the return of you all is to Me, and I will tell you the truth (and meaning) of all that ye did."

9. **34:6** (score 0.533) `[unlabelled]`
   > And those to whom knowledge has come see that the (Revelation) sent down to thee from thy Lord - that is the Truth, and that it guides to the Path of the Exalted (in might), Worthy of all praise.

10. **31:34** (score 0.532) `[unlabelled]`
   > Verily the knowledge of the Hour is with Allah (alone). It is He Who sends down rain, and He Who knows what is in the wombs. Nor does any one know what it is that he will earn on the morrow: Nor does any one know in what land he is to die. Verily with Allah is full knowledge and He is acquainted (with all things).

Labelled but not retrieved in the top 10: `16:78`, `39:9`, `96:1`

---

## Query 12: what does the Quran say about the poor and needy

Currently labelled relevant: `2:215`, `2:271`, `2:273`, `9:60`

1. **59:9** (score 0.614) `[unlabelled]`
   > But those who before them, had homes (in Medina) and had adopted the Faith,- show their affection to such as came to them for refuge, and entertain no desire in their hearts for things given to the (latter), but give them preference over themselves, even though poverty was their (own lot). And those saved from the covetousness of their own souls,- they are the ones that achieve prosperity.

2. **10:58** (score 0.582) `[unlabelled]`
   > Say: "In the bounty of Allah. And in His Mercy,- in that let them rejoice": that is better than the (wealth) they hoard.

3. **76:8** (score 0.578) `[unlabelled]`
   > And they feed, for the love of Allah, the indigent, the orphan, and the captive,-

4. **107:3** (score 0.566) `[unlabelled]`
   > And encourages not the feeding of the indigent.

5. **71:21** (score 0.558) `[unlabelled]`
   > Noah said: "O my Lord! They have disobeyed me, but they follow (men) whose wealth and children give them no increase but only Loss.

6. **34:39** (score 0.555) `[unlabelled]`
   > Say: "Verily my Lord enlarges and restricts the Sustenance to such of his servants as He pleases: and nothing do ye spend in the least (in His cause) but He replaces it: for He is the Best of those who grant Sustenance.

7. **63:7** (score 0.553) `[unlabelled]`
   > They are the ones who say, "Spend nothing on those who are with Allah's Messenger, to the end that they may disperse (and quit Medina)." But to Allah belong the treasures of the heavens and the earth; but the Hypocrites understand not.

8. **11:29** (score 0.551) `[unlabelled]`
   > "And O my people! I ask you for no wealth in return: my reward is from none but Allah: But I will not drive away (in contempt) those who believe: for verily they are to meet their Lord, and ye I see are the ignorant ones!

9. **4:5** (score 0.550) `[unlabelled]`
   > To those weak of understanding Make not over your property, which Allah hath made a means of support for you, but feed and clothe them therewith, and speak to them words of kindness and justice.

10. **106:4** (score 0.545) `[unlabelled]`
   > Who provides them with food against hunger, and with security against fear (of danger).

Labelled but not retrieved in the top 10: `2:215`, `2:271`, `2:273`, `9:60`

---

## Query 13: what does the Quran say about stress and hardship

Currently labelled relevant: `2:286`, `65:3`, `94:5`, `94:6`

1. **21:83** (score 0.551) `[unlabelled]`
   > And (remember) Job, when He cried to his Lord, "Truly distress has seized me, but Thou art the Most Merciful of those that are merciful."

2. **94:5** (score 0.547) **[labelled]**
   > So, verily, with every difficulty, there is relief:

3. **2:286** (score 0.546) **[labelled]**
   > On no soul doth Allah Place a burden greater than it can bear. It gets every good that it earns, and it suffers every ill that it earns. (Pray:) "Our Lord! Condemn us not if we forget or fall into error; our Lord! Lay not on us a burden Like that which Thou didst lay on those before us; Our Lord! Lay not on us a burden greater than we have strength to bear. Blot out our sins, and grant us forgiveness. Have mercy on us. Thou art our Protector; Help us against those who stand against faith."

4. **94:7** (score 0.543) `[unlabelled]`
   > Therefore, when thou art free (from thine immediate task), still labour hard,

5. **94:6** (score 0.535) **[labelled]**
   > Verily, with every difficulty there is relief.

6. **88:3** (score 0.531) `[unlabelled]`
   > Labouring (hard), weary,-

7. **12:86** (score 0.523) `[unlabelled]`
   > He said: "I only complain of my distraction and anguish to Allah, and I know from Allah that which ye know not...

8. **11:106** (score 0.516) `[unlabelled]`
   > Those who are wretched shall be in the Fire: There will be for them therein (nothing but) the heaving of sighs and sobs:

9. **53:38** (score 0.511) `[unlabelled]`
   > Namely, that no bearer of burdens can bear the burden of another;

10. **6:17** (score 0.511) `[unlabelled]`
   > "If Allah touch thee with affliction, none can remove it but He; if He touch thee with happiness, He hath power over all things.

Labelled but not retrieved in the top 10: `65:3`

---

## Query 14: what does the Quran say about responding to wrongdoing

Currently labelled relevant: `16:126`, `41:34`, `4:148`, `5:8`

1. **14:42** (score 0.644) `[unlabelled]`
   > Think not that Allah doth not heed the deeds of those who do wrong. He but giveth them respite against a Day when the eyes will fixedly stare in horror,-

2. **10:106** (score 0.630) `[unlabelled]`
   > "'Nor call on any, other than Allah;- Such will neither profit thee nor hurt thee: if thou dost, behold! thou shalt certainly be of those who do wrong.'"

3. **40:35** (score 0.627) `[unlabelled]`
   > "(Such) as dispute about the Signs of Allah, without any authority that hath reached them, grievous and odious (is such conduct) in the sight of Allah and of the Believers. Thus doth Allah, seal up every heart - of arrogant and obstinate Transgressors."

4. **16:90** (score 0.618) `[unlabelled]`
   > Allah commands justice, the doing of good, and liberality to kith and kin, and He forbids all shameful deeds, and injustice and rebellion: He instructs you, that ye may receive admonition.

5. **21:112** (score 0.611) `[unlabelled]`
   > Say: "O my Lord! judge Thou in truth!" "Our Lord Most Gracious is the One Whose assistance should be sought against the blasphemies ye utter!"

6. **47:4** (score 0.604) `[unlabelled]`
   > Therefore, when ye meet the Unbelievers (in fight), smite at their necks; At length, when ye have thoroughly subdued them, bind a bond firmly (on them): thereafter (is the time for) either generosity or ransom: Until the war lays down its burdens. Thus (are ye commanded): but if it had been Allah's Will, He could certainly have exacted retribution from them (Himself); but (He lets you fight) in order to test you, some with others. But those who are slain in the Way of Allah,- He will never let their deeds be lost.

7. **5:118** (score 0.600) `[unlabelled]`
   > "If Thou dost punish them, they are Thy servant: If Thou dost forgive them, Thou art the Exalted in power, the Wise."

8. **39:8** (score 0.599) `[unlabelled]`
   > When some trouble toucheth man, he crieth unto his Lord, turning to Him in repentance: but when He bestoweth a favour upon him as from Himself, (man) doth forget what he cried and prayed for before, and he doth set up rivals unto Allah, thus misleading others from Allah's Path. Say, "Enjoy thy blasphemy for a little while: verily thou art (one) of the Companions of the Fire!"

9. **9:68** (score 0.595) `[unlabelled]`
   > Allah hath promised the Hypocrites men and women, and the rejecters, of Faith, the fire of Hell: Therein shall they dwell: Sufficient is it for them: for them is the curse of Allah, and an enduring punishment,-

10. **40:42** (score 0.589) `[unlabelled]`
   > "Ye do call upon me to blaspheme against Allah, and to join with Him partners of whom I have no knowledge; and I call you to the Exalted in Power, Who forgives again and again!"

Labelled but not retrieved in the top 10: `16:126`, `41:34`, `4:148`, `5:8`

---

## Query 15: what is the proper way to baptize an infant in Islam

Currently labelled relevant: *none - this is a negative query*

1. **20:39** (score 0.468) `[unlabelled]`
   > "'Throw (the child) into the chest, and throw (the chest) into the river: the river will cast him up on the bank, and he will be taken up by one who is an enemy to Me and an enemy to him': But I cast (the garment of) love over thee from Me: and (this) in order that thou mayest be reared under Mine eye.

2. **2:138** (score 0.455) `[unlabelled]`
   > (Our religion is) the Baptism of Allah: And who can baptize better than Allah? And it is He Whom we worship.

3. **73:4** (score 0.414) `[unlabelled]`
   > Or a little more; and recite the Qur'an in slow, measured rhythmic tones.

4. **20:40** (score 0.405) `[unlabelled]`
   > "Behold! thy sister goeth forth and saith, 'shall I show you one who will nurse and rear the (child)?' So We brought thee back to thy mother, that her eye might be cooled and she should not grieve. Then thou didst slay a man, but We saved thee from trouble, and We tried thee in various ways. Then didst thou tarry a number of years with the people of Midian. Then didst thou come hither as ordained, O Moses!

5. **5:6** (score 0.386) `[unlabelled]`
   > O ye who believe! when ye prepare for prayer, wash your faces, and your hands (and arms) to the elbows; Rub your heads (with water); and (wash) your feet to the ankles. If ye are in a state of ceremonial impurity, bathe your whole body. But if ye are ill, or on a journey, or one of you cometh from offices of nature, or ye have been in contact with women, and ye find no water, then take for yourselves clean sand or earth, and rub therewith your faces and hands, Allah doth not wish to place you in a difficulty, but to make you clean, and to complete his favour to you, that ye may be grateful.

6. **50:40** (score 0.368) `[unlabelled]`
   > And during part of the night, (also,) celebrate His praises, and (so likewise) after the postures of adoration.

7. **28:12** (score 0.364) `[unlabelled]`
   > And we ordained that he refused suck at first, until (His sister came up and) said: "Shall I point out to you the people of a house that will nourish and bring him up for you and be sincerely attached to him?"...

8. **42:49** (score 0.361) `[unlabelled]`
   > To Allah belongs the dominion of the heavens and the earth. He creates what He wills (and plans). He bestows (children) male or female according to His Will (and Plan),

9. **19:27** (score 0.361) `[unlabelled]`
   > At length she brought the (babe) to her people, carrying him (in her arms). They said: "O Mary! truly an amazing thing hast thou brought!

10. **76:17** (score 0.359) `[unlabelled]`
   > And they will be given to drink there of a Cup (of Wine) mixed with Zanjabil,-

---

## Query 16: what is the best Islamic stock portfolio strategy

Currently labelled relevant: *none - this is a negative query*

1. **31:5** (score 0.399) `[unlabelled]`
   > These are on (true) guidance from their Lord: and these are the ones who will prosper.

2. **3:130** (score 0.387) `[unlabelled]`
   > O ye who believe! Devour not usury, doubled and multiplied; but fear Allah; that ye may (really) prosper.

3. **73:4** (score 0.380) `[unlabelled]`
   > Or a little more; and recite the Qur'an in slow, measured rhythmic tones.

4. **2:279** (score 0.377) `[unlabelled]`
   > If ye do it not, Take notice of war from Allah and His Messenger: But if ye turn back, ye shall have your capital sums: Deal not unjustly, and ye shall not be dealt with unjustly.

5. **64:16** (score 0.377) `[unlabelled]`
   > So fear Allah as much as ye can; listen and obey and spend in charity for the benefit of your own soul and those saved from the covetousness of their own souls,- they are the ones that achieve prosperity.

6. **47:21** (score 0.376) `[unlabelled]`
   > Were it to obey and say what is just, and when a matter is resolved on, it were best for them if they were true to Allah.

7. **2:5** (score 0.357) `[unlabelled]`
   > They are on (true) guidance, from their Lord, and it is these who will prosper.

8. **11:34** (score 0.356) `[unlabelled]`
   > "Of no profit will be my counsel to you, much as I desire to give you (good) counsel, if it be that Allah willeth to leave you astray: He is your Lord! and to Him will ye return!"

9. **31:1** (score 0.352) `[unlabelled]`
   > A. L. M.

10. **106:1** (score 0.343) `[unlabelled]`
   > For the covenants (of security and safeguard enjoyed) by the Quraish,

---

## Query 17: what does the Quran say about patience and trust in Allah

Currently labelled relevant: `2:153`, `31:17`, `94:5`, `94:6`

1. **14:12** (score 0.665) `[unlabelled]`
   > "No reason have we why we should not put our trust on Allah. Indeed He Has guided us to the Ways we (follow). We shall certainly bear with patience all the hurt you may cause us. For those who put their trust should put their trust on Allah."

2. **30:60** (score 0.651) `[unlabelled]`
   > So patiently persevere: for verily the promise of Allah is true: nor let those shake thy firmness, who have (themselves) no certainty of faith.

3. **10:84** (score 0.626) `[unlabelled]`
   > Moses said: "O my people! If ye do (really) believe in Allah, then in Him put your trust if ye submit (your will to His)."

4. **70:5** (score 0.559) `[unlabelled]`
   > Therefore do thou hold Patience,- a Patience of beautiful (contentment).

5. **18:67** (score 0.552) `[unlabelled]`
   > (The other) said: "Verily thou wilt not be able to have patience with me!"

6. **18:68** (score 0.552) `[unlabelled]`
   > "And how canst thou have patience about things about which thy understanding is not complete?"

7. **11:115** (score 0.513) `[unlabelled]`
   > And be steadfast in patience; for verily Allah will not suffer the reward of the righteous to perish.

8. **10:85** (score 0.513) `[unlabelled]`
   > They said: "In Allah do we put out trust. Our Lord! make us not a trial for those who practise oppression;

9. **18:69** (score 0.512) `[unlabelled]`
   > Moses said: "Thou wilt find me, if Allah so will, (truly) patient: nor shall I disobey thee in aught."

10. **12:64** (score 0.511) `[unlabelled]`
   > He said: "Shall I trust you with him with any result other than when I trusted you with his brother aforetime? But Allah is the best to take care (of him), and He is the Most Merciful of those who show mercy!"

Labelled but not retrieved in the top 10: `2:153`, `31:17`, `94:5`, `94:6`

---
