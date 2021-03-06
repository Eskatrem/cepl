;; This software is Copyright (c) 2012 Chris Bagley
;; (techsnuffle<at>gmail<dot>com)
;; Chris Bagley grants you the rights to
;; distribute and use this software as governed
;; by the terms of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.

;; This package is for all the vector4 math functions
;; There will be a generic function-set to make this as easy
;; as possible for people writing the games but this will 
;; be in a seperate package (prehaps the base-maths one)

(in-package #:vector4)


;;; [TODO] make destructive versions aswell
;;; looking at some existing code the desctructive versions
;;; end up being comparitively fast to C. 
;;; see http://stackoverflow.com/questions/8356494/efficient-vector-operations-of-linear-algebra-in-common-lisp-especially-sbcl for more details

;;; Also see http://nklein.com/2009/06/speedy-matrix-multiplication-in-lisp-again/ for a nice guide to declaim and its effects.

;;; Annoyingly as everything else is reliant on the speed of the 
;;; vector math I have to make this bit fast, this seems to mean
;;; hardcoding for set structures sizes. I hope I'm wrong and I
;;; can use loops and have lisp be clever enough to optomize it
;;; but for now I'm not counting on it
;;; Also we will be making use of declaim for inlining and also 
;;; for forcing float type on everything.

;;; vector4 operations

;----------------------------------------------------------------

(declaim (inline make-vector4)
	 (ftype (function ((single-float) 
			   (single-float) 
			   (single-float)
			   (single-float)) 
			  (simple-array single-float (4))) 
		make-vector4))
(defun make-vector4 (x y z w)
  "This takes 4 floats and give back a vector4, this is just an
   array but it specifies the array type and populates it. 
   For speed reasons it will not accept integers so make sure 
   you hand it floats."
  (declare (single-float x y z w))
  (let (( vec (make-array 4 :element-type `single-float)))
    (setf (aref vec 0) x
	  (aref vec 1) y
	  (aref vec 2) z
	  (aref vec 3) w)
    vec))

;----------------------------------------------------------------

;; Not sure what I'm going to do with these. I don't belive this
;; is the best way to do this as it doesnt give a new vector
;; not that lispy
(defparameter *unit-x* (vector 1.0 0.0 0.0 0.0))
(defparameter *unit-y* (vector 0.0 1.0 0.0 0.0))
(defparameter *unit-z* (vector 0.0 0.0 1.0 0.0))
(defparameter *unit-w* (vector 0.0 0.0 0.0 1.0))
(defparameter *unit-scale* (vector 1.0 1.0 1.0 1.0))
(defparameter *origin* (vector 0.0 0.0 0.0 0.0))

;----------------------------------------------------------------

;;[TODO] What is faster (* x x) or (expt x 2) ?
(declaim (inline vzerop)
	 (ftype (function ((simple-array single-float (4))) 
			  (boolean)) vzerop))
(defun vzerop (vector-a)
  "Checks if the length of the vector is zero. As this is a 
   floating point number it checks to see if the length is
   below a threshold set in the base-maths package"
  (declare ((simple-array single-float (4)) vector-a))
  (float-zero (apply-across-elements + ((vc-a vector-a)) 4
		   (expt vc-a 2))))

;----------------------------------------------------------------

(declaim (inline unitp)
	 (ftype (function ((simple-array single-float (4))) 
			  (boolean)) unitp))
(defun unitp (vector-a)
  "Checks if the vector is of unit length. As this is a 
   floating point number it checks to see if the length is
   within the range of 1 + or - and threshold set in base-maths"
  (declare ((simple-array single-float (4)) vector-a))
  (float-zero (- 1.0 (apply-across-elements + ((vc-a vector-a)) 4
			  (expt vc-a 2)))))
;----------------------------------------------------------------

;; Would be interesting to see if checking that the arrays
;; are not 'eq' first would speed this up 
(declaim (inline v-eq)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (boolean)) v-eq))
(defun v-eq (vector-a vector-b)
  "Returns either t if the two vectors are equal. 
   Otherwise it returns nil."
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements and ((vc-a vector-a) (vc-b vector-b)) 4
    (= vc-a vc-b)))

;----------------------------------------------------------------

;; Not sure how to optomise this
(defun v+ (&rest vec4s)
  "takes any number of vectors and add them all together 
   returning a new vector"
  (reduce #'v+1 vec4s))

;----------------------------------------------------------------

(declaim (inline v+1)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (simple-array single-float (4))) v+1))
(defun v+1 (vector-a vector-b)
  "Add two vectors and return a new vector containing the result"
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements make-vector4 ((vc-a vector-a) 
				       (vc-b vector-b)) 4
    (+ vc-a vc-b)))

;----------------------------------------------------------------

;; Not sure how to optomise this
(defun v- (&rest vec4s)
  "takes any number of vectors and subtract them and return
   a new vector4"
  (reduce #'v-1 vec4s))

;----------------------------------------------------------------

(declaim (inline v-1)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (simple-array single-float (4))) v-1))
(defun v-1 (vector-a vector-b)
  "Subtract two vectors and return a new vector containing 
   the result"
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements make-vector4 ((vc-a vector-a) 
				       (vc-b vector-b)) 4
    (- vc-a vc-b)))

;----------------------------------------------------------------

(declaim (inline v*)
	 (ftype (function ((simple-array single-float (4)) 
			   (single-float)) 
			  (simple-array single-float (4))) v*))
(defun v* (vector-a a)
  "Multiply vector by scalar"
  (declare ((simple-array single-float (4)) vector-a)
	   ((single-float) a))
  (apply-across-elements make-vector4 ((vc-a vector-a)) 4
    (* vc-a a)))

;----------------------------------------------------------------

(declaim (inline v3*)
	 (ftype (function ((simple-array single-float (4)) 
			   (single-float)) 
			  (simple-array single-float (4))) v3*))
(defun v3* (vector-a a)
  "Multiply vector by scalar"
  (declare ((simple-array single-float (4)) vector-a)
	   ((single-float) a))
  (make-vector4 (* (aref vector-a 0) a) (* (aref vector-a 1) a)
              (* (aref vector-a 2) a) (aref vector-a 3)))

;----------------------------------------------------------------

(declaim (inline v*vec)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (simple-array single-float (4))) 
		v*vec))
(defun v*vec (vector-a vector-b) 
  "Multiplies components, is not dot product, not sure what
   i'll need this for yet but hey!"
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements make-vector4 ((vc-a vector-a) 
				       (vc-b vector-b)) 4
    (* vc-a vc-b)))

;----------------------------------------------------------------

;;; may just be an evil side effect of ripping this off from
;;; from ogre but some of the optomisations will be coming over
;;; as well, this may not be relevent in lisp, I will see later
;;; on.
(declaim (inline v/)
	 (ftype (function ((simple-array single-float (4)) 
			   (single-float)) 
			  (simple-array single-float (4))) v/))
(defun v/ (vector-a a)
  "divide vector by scalar and return result as new vector"
  (declare ((simple-array single-float (4)) vector-a)
	   ((single-float) a))
  (let ((b (/ 1 a)))
    (apply-across-elements make-vector4 ((vc-a vector-a)) 4
      (* vc-a b))))

;----------------------------------------------------------------

(declaim (inline v/vec)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (simple-array single-float (4))) 
		v/vec))
(defun v/vec (vector-a vector-b) 
  "Divides components, not sure what, i'll need this for 
   yet but hey!"
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements make-vector4 ((vc-a vector-a) 
				       (vc-b vector-b)) 4
      (/ vc-a vc-b)))

;----------------------------------------------------------------

(declaim (inline negate)
	 (ftype (function ((simple-array single-float (4))) 
			  (simple-array single-float (4))) 
		negate))
(defun negate (vector-a)
  "Return a vector that is the negative of the vector passed in"
  (declare ((simple-array single-float (4)) vector-a))
  (apply-across-elements make-vector4 ((vc-a vector-a)) 4
    (- vc-a)))

;----------------------------------------------------------------

(declaim (inline vlength-squared)
	 (ftype (function ((simple-array single-float (4))) 
			  (single-float)) vlength-squared))
(defun vlength-squared (vector-a)
  "Return the squared length of the vector. A regular length
   is the square root of this value. The sqrt function is slow
   so if all thats needs doing is to compare lengths then always
   use the length squared function"
  (declare ((simple-array single-float (4)) vector-a))
  (let ((x (v-x vector-a))
	(y (v-y vector-a))
	(z (v-z vector-a))
	(w (v-w vector-a)))
    (+ (* x x) (* y y) (* z z) (* w w))))

;----------------------------------------------------------------

(declaim (inline vlength)
	 (ftype (function ((simple-array single-float (4))) 
			  (single-float)) vlength))
(defun vlength (vector-a)
  "Returns the length of a vector
   If you only need to compare relative lengths then definately
   stick to length-squared as the sqrt is a slow operation."
  (declare ((simple-array single-float (4)) vector-a))
  (c-sqrt (vlength-squared vector-a)))

;----------------------------------------------------------------

(declaim (inline distance-squared)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (single-float)) 
		distance-squared))
(defun distance-squared (vector-a vector-b)
  "finds the squared distance between 2 points defined by vectors
   vector-a & vector-b"
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (vlength-squared (v- vector-b vector-a)))

;----------------------------------------------------------------

(declaim (inline distance)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (single-float)) 
		distance))
(defun distance (vector-a vector-b)
  "Return the distance between 2 points defined by vectors 
   vector-a & vector-b. If comparing distances, use 
   c-distance-squared as it desnt require a c-sqrt and thus is 
   faster."
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (c-sqrt (distance-squared vector-a vector-b)))

;----------------------------------------------------------------

(declaim (inline dot)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (single-float)) 
		dot))
(defun dot (vector-a vector-b)
  "Return the dot product of the vector-a and vector-b."
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements + ((vc-a vector-a) 
				       (vc-b vector-b)) 4
    (* vc-a vc-b)))

;----------------------------------------------------------------

(declaim (inline absolute-dot)
	 (ftype (function ((simple-array single-float (4)) 
			   (simple-array single-float (4))) 
			  (single-float)) 
		absolute-dot))
(defun absolute-dot (vector-a vector-b) 
  "Return the absolute dot product of the vector-a and vector-b."
  (declare ((simple-array single-float (4)) vector-a vector-b))
  (apply-across-elements + ((vc-a vector-a) 
			    (vc-b vector-b)) 4
    (abs (* vc-a vc-b))))

;----------------------------------------------------------------

;; [TODO] shouldnt this return a zero vector in event of zero 
;; length? does it matter?
(declaim (inline normalize)
	 (ftype (function ((simple-array single-float (4))) 
			  (simple-array single-float (4))) 
		normalize))
(defun normalize (vector-a)
  "This normalizes the vector, it makes sure a zero length
   vector won't throw an error."
  (declare ((simple-array single-float (4)) vector-a))
  (let ((len (vlength-squared vector-a))) 
    (if (float-zero len)
	vector-a
	(v* vector-a (c-inv-sqrt len)))))

;----------------------------------------------------------------
