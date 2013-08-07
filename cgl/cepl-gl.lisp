;; This software is Copyright (c) 2012 Chris Bagley
;; (techsnuffle<at>gmail<dot>com)
;; Chris Bagley grants you the rights to
;; distribute and use this software as governed
;; by the terms of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.

;; This is to provide abstractions over the cl-opengl-bindings
;;
;; It is designed to be the 'thinnest' possible wrapper around
;; (cl)opengl 2.1+ which abstracts the ugly stuff without taking
;; away any of the functionality.
;;
;; The key design axioms are:
;; * OpenGl is 2 paradigms in one API with totally different
;;   methodologies and approaches to development. It is better
;;   to make 2 wrappers that seperate and abstract these
;;   methodologies well, rather than to try and cram both
;;   together.
;;   To this end cepl-gl will only support modern opengl (2.1+).
;;
;; * It should be possible to write a 'hello world' opengl
;;   example from a tutorial online without abstractions getting
;;   in the way.
;;   Abstractions, in their effort to simplify complex code, can
;;   balloon simple code. This is unacceptable.
;;   Part of the beauty of lisp is being able to blast out a
;;   quick example in the repl and we must not allow our attempts
;;   to simplify things to take any of that beauty away.
;;

(in-package :cepl-gl)

(defcfun (%memcpy "memcpy") :pointer  
  (destination-pointer :pointer)
  (source-pointer :pointer)
  (byte-length :long))

;;;--------------------------------------------------------------
;;; GLARRAYS ;;;
;;;----------;;;

(defmacro with-gl-array ((var-name type length &optional initial-contents)
                         &body body)
  `(let* ((,var-name (make-gl-array ,type ,length
                                    ,@(when initial-contents
                                            (list initial-contents)))))
     (unwind-protect
          (progn ,@body)
       (free-gl-array ,var-name))))

(defmacro with-gl-arrays ((array-list-var arrays) &body body)
  `(let ((,array-list-var ,arrays))
     (unwind-protect
          (progn ,@body)
       (loop for array in ,array-list-var :do (free-gl-array array)))))

(defun make-gl-array-from-pointer (ptr element-type length)
  (make-gl-array element-type length nil ptr))

(defun gl-array-byte-size (gl-array)
  "This returns the size in bytes of the gl-array"
  (* (array-length gl-array) 
     (cffi:foreign-type-size (array-type gl-array))))

(defun gl-array-dimensions (gl-array)
  (array-length gl-array))

(defun free-gl-array (gl-array)
  "Frees the specified gl-array."
  (foreign-free (pointer gl-array)))

(declaim (inline aref-gl-ptr))
(defun aref-gl-ptr (gl-array index)
  "Returns the INDEX-th component of gl-array."
  (mem-aref (pointer gl-array) (array-type gl-array) index))

(declaim (inline (setf aref-gl-ptr)))
(defun (setf aref-gl-ptr) (value array index)
  "Sets the INDEX-th component of gl-array. to value"
  (setf (mem-aref (pointer array) (array-type array) index) 
        value))

(defgeneric aref-gl (gl-array index)
  (:documentation ""))

(defgeneric (setf aref-gl) (value gl-array index)
  (:documentation ""))

(defmethod aref-gl ((gl-array gl-array) index)
  (glpull-entry gl-array index))

(defmethod aref-gl ((gl-array gl-struct-array) index)
  (make-instance 'gl-value
                 :type (array-type gl-array)
                 :len 1
                 :pointer (mem-aptr (pointer gl-array) (array-type gl-array)
                                    index)))

(defmethod (setf aref-gl) (value (gl-array gl-array) index)
  (glpush-entry gl-array index value))

(defun destructuring-allocate (array-type data)
  "This function will create a new gl-array with a length
   equal to the length of the data provided, and then populate 
   the gl-array.

   The data must be a list of sublists. Each sublist must
   contain the data for the attributes of the gl-array's type.  
   That sucks as an explanation so here is an example:

   given a format as defined below:
    (cgl:define-interleaved-attribute-format vert-data 
      (:type :float :components (x y z))
      (:type :float :components (r g b a)))

   and an array made using this format
    (setf *vertex-data-gl* (cgl:make-gl-array 'vert-data :length 3))

   then you can populate it as so:
    (cgl:destructuring-populate *vertex-data-gl*
     	   '((#( 0.0     0.5  0.0)
		      #( 1.0     0.0  0.0  1.0))

			 (#( 0.5  -0.366  0.0)
			  #( 0.0     1.0  0.0  1.0))

			 (#(-0.5  -0.366  0.0)
			  #( 0.0     0.0  1.0  1.0))))

   Hopefully that makes sense."
  (let ((array (make-gl-array array-type (length data))))
    (destructuring-populate array data)
    array))

;;;--------------------------------------------------------------
;;; BUFFERS ;;;
;;;---------;;;

(defstruct glbuffer
  "This is our opengl buffer object. Along with the opengl
   buffer name (buffer-id) we also store the layout of the data
   within the buffer. 
   This layout is as follows:
   `((data-type data-index-length offset-in-bytes-into-buffer)
   for example:
   `((:float 10 0) ('vert-data 50 40))"
  (buffer-id (car (gl:gen-buffers 1)))
  (format nil))

(let ((buffer-id-cache nil)
      (buffer-target-cache nil))
  (defun bind-buffer (buffer buffer-target)
    "Binds the specified opengl buffer to the target"
    (let ((id (glbuffer-buffer-id buffer)))
      (unless (and (eq id buffer-id-cache) 
                   (eq buffer-target buffer-target-cache))
        (cl-opengl-bindings:bind-buffer buffer-target id)
        (setf buffer-target-cache id)
        (setf buffer-target-cache buffer-target))))
  (defun force-bind-buffer (buffer buffer-target)
    "Binds the specified opengl buffer to the target"
    (let ((id (glbuffer-buffer-id buffer)))
      (cl-opengl-bindings:bind-buffer buffer-target id)
      (setf buffer-id-cache id)
      (setf buffer-target-cache buffer-target)))
  (defun unbind-buffer ()
    (cl-opengl-bindings:bind-buffer :array-buffer 0)
    (setf buffer-id-cache 0)
    (setf buffer-target-cache :array-buffer)))

(defun gen-buffer (&key initial-contents 
                     (buffer-target :array-buffer) 
                     (usage :static-draw))
  (declare (symbol buffer-target usage))
  "Creates a new opengl buffer object. 
   Optionally you can provide a gl-array as the :initial-contents
   to have the buffer populated with the contents of the array"
  (let ((new-buffer (make-glbuffer)))
    (if initial-contents
        (buffer-data new-buffer initial-contents buffer-target
                     usage)
        new-buffer)))

;; buffer format is a list whose sublists are of the format
;; type, index-length, byte-offset-from-start-of-buffer

(defun buffer-data (buffer gl-array buffer-target usage
                    &key (offset 0)
                      (size (gl-array-byte-size gl-array)))
  "This function populates an opengl buffer with the contents 
   of the array. You also pass in the buffer type and the 
   draw type this buffer is to be used for.
   
   The function returns a buffer object with its format slot
   populated with the details of the data stored within the buffer"
  (bind-buffer buffer buffer-target)
  (%gl:buffer-data buffer-target 
                   size
                   (cffi:inc-pointer (pointer gl-array)
                                     (foreign-type-index (array-type gl-array)
                                                         offset))
                   usage)
  (setf (glbuffer-format buffer) 
        (list (list (array-type gl-array) (array-length gl-array) 0)))
  buffer)


(defun buffer-sub-data (buffer gl-array byte-offset buffer-target
                        &key (safe t))  
  "This function replaces a subsection of the data in the 
   specified buffer with the data in the gl-array.
   The byte offset specified where you wish to start overwriting 
   data from. 
   When the :safe option is t, the function checks to see if the 
   data you are about to write into the buffer will cross the 
   boundaries between data already in the buffer and will emit 
   an error if you are."
  (let ((byte-size (gl-array-byte-size gl-array)))
    (when (and safe (loop for format in (glbuffer-format buffer)
                       when (and (< byte-offset (third format))
                                 (> (+ byte-offset byte-size)
                                    (third format)))
                       return t))
      (error "The data you are trying to sub into the buffer crosses the boundaries specified in the buffer's format. If you want to do this anyway you should set :safe to nil, though it is not advised as your buffer format would be invalid"))
    (bind-buffer buffer buffer-target)
    (%gl:buffer-sub-data buffer-target
                         byte-offset
                         byte-size
                         (pointer gl-array)))
  buffer)


(defun multi-buffer-data (buffer arrays buffer-target usage)
  "This beast will take a list of arrays and auto-magically
   push them into a buffer taking care of both interleaving 
   and sequencial data and handling all the offsets."
  (let* ((array-byte-sizes (loop for array in arrays
                              collect 
                                (gl-array-byte-size array)))
         (total-size (apply #'+ array-byte-sizes)))
    (bind-buffer buffer buffer-target)
    (buffer-data buffer (first arrays) buffer-target usage
                 :size total-size)
    (setf (glbuffer-format buffer) 
          (loop for gl-array in arrays
             for size in array-byte-sizes
             with offset = 0
             collect (list (array-type gl-array)
                           (array-length gl-array)
                           offset)
             do (buffer-sub-data buffer gl-array offset
                                 buffer-target)
               (setf offset (+ offset size)))))
  buffer)

(defun buffer-reserve-raw-block (buffer size-in-bytes buffer-target 
                                 usage)
  "This function creates an empty block of data in the opengl buffer.
   It will remove ALL data currently in the buffer. It also will not
   update the format of the buffer so you must be sure to handle this
   yourself. It is much safer to use this as an assistant function to
   one which takes care of these issues"
  (bind-buffer buffer buffer-target)
  (%gl:buffer-data buffer-target size-in-bytes
                   (cffi:null-pointer) usage)
  buffer)

(defun buffer-reserve-block (buffer type length buffer-target usage)
  "This function creates an empty block of data in the opengl buffer
   equal in size to (* length size-in-bytes-of-type).
   It will remove ALL data currently in the buffer"
  (bind-buffer buffer buffer-target)
  (buffer-reserve-raw-block buffer
                            (foreign-type-index type length)
                            buffer-target
                            usage)
  ;; make format
  (setf (glbuffer-format buffer) `((,type ,length ,0)))
  buffer)

(defun buffer-reserve-blocks (buffer types-and-lengths
                              buffer-target usage)
  "This function creates an empty block of data in the opengl buffer
   equal in size to the sum of all of the 
   (* length size-in-bytes-of-type) in types-and-lengths.
   types-and-lengths should be of the format:
   `((type length) (type length) ...etc)
   It will remove ALL data currently in the buffer"
  (let ((size-in-bytes 0))
    (setf (glbuffer-format buffer) 
          (loop for (type length)
             in types-and-lengths
             do (incf size-in-bytes 
                      (foreign-type-index type length))
             collect `(,type ,length ,size-in-bytes)))
    (buffer-reserve-raw-block buffer size-in-bytes
                              buffer-target usage)
    buffer))

;;;--------------------------------------------------------------
;;; GPUARRAYS ;;;
;;;-----------;;;

;; [TODO] Implement buffer freeing properly
(let ((buffer-pool nil))
  (defun add-buffer-to-pool (buffer)
    (setf buffer-pool (cons buffer buffer-pool))
    buffer)

  (defun free-all-buffers-in-pool ()
    (mapcar #'(lambda (x) (declare (ignore x))
                      (print "freeing a buffer")) 
            buffer-pool)))

(defstruct gpuarray 
  buffer
  format-index
  (start 0)
  length
  index-array 
  (access-style :static-draw))

(defmethod print-object ((object gpuarray) stream)
  (format stream 
          "#.<~a :type ~s :length ~a>"
          (if (gpuarray-index-array object)
              "GPU-INDEX-ARRAY"
              "GPU-ARRAY")
          (gpuarray-type object)
          (gpuarray-length object)))

(defun gpuarray-format (gpu-array)
  "Returns a list containing the element-type, the length of the
   array and the offset in bytes from the beginning of the buffer
   this gpu-array lives in."
  (nth (gpuarray-format-index gpu-array)
       (glbuffer-format (gpuarray-buffer gpu-array))))

;; (defmethod array-type (gpu-array gpuarray)
;;   "Returns the type of the gpuarray"
;;   (first (gpuarray-format gpu-array)))

(defun gpuarray-type (gpu-array)
  "Returns the type of the gpuarray"
  (first (gpuarray-format gpu-array)))

(defun gpuarray-offset (gpu-array)
  "Returns the offset in bytes from the beggining of the buffer
   that this gpuarray is stored at"
  (let ((format (gpuarray-format gpu-array)))
    (+ (third format)
       (foreign-type-index (first format)
                           (gpuarray-start gpu-array)))))

(defun pull-gl-arrays-from-buffer (buffer)
  (loop :for attr-format :in (glbuffer-format buffer)
     :collect 
     (progn 
       (bind-buffer buffer :array-buffer)
       (gl:with-mapped-buffer (b-pointer :array-buffer :read-only)
         
         (let* ((array-type (first attr-format))
                (gl-array (make-gl-array (if (listp array-type)
                                             (if (eq :struct (first array-type))
                                                 (second array-type)
                                                 (error "we dont handle arrays of pointers yet"))
                                             array-type)
                                        (second attr-format))))
           (%memcpy (pointer gl-array) 
                    (cffi:inc-pointer b-pointer (third attr-format))
                    (gl-array-byte-size gl-array))
           gl-array)))))

(defgeneric make-gpu-array (initial-contents &key)
  (:documentation "This function creates a gpu-array which is very similar
   to a gl-array except that it is located in the memory of the
   graphics card and so is accesable to shaders.
   You can either provide and type and length or you can 
   provide a gl-array and the data from that will be used to 
   populate the gpu-array with.

   If this array is to be used as an index array then set the 
   :index-array key to t

   Access style is optional but if you are comfortable with 
   opengl, and know what type of usage pattern thsi array will
   have, you can set this to any of the following:
   (:stream-draw​ :stream-read​ :stream-copy​ :static-draw​ 
    :static-read​ :static-copy​ :dynamic-draw​ :dynamic-read
   ​ :dynamic-copy)

   Finally you can provide an existing buffer if you want to
   append the new array into that buffer. This is VERY slow
   compared to other ways of creating arrays and should only
   really be used in non-production code or when just playing 
   around in the REPL"))

(defmethod make-gpu-array ((initial-contents null) 
                           &key element-type length (index-array nil)
                             (access-style :static-draw) (location nil))
  (declare (ignore initial-contents))
  (if location
      (with-gl-arrays (arrays (append (pull-gl-arrays-from-buffer location)
                                      (list (make-gl-array element-type 
                                                           :length length))))
        (car (last (make-gpu-arrays arrays :index-array index-array
                                    :access-style access-style
                                    :location location))))      
      (let ((buffer (add-buffer-to-pool (gen-buffer))))
        (make-gpuarray :buffer (buffer-reserve-block buffer 
                                                     element-type
                                                     length
                                                     (if index-array
                                                         :element-array-buffer
                                                         :array-buffer)
                                                     access-style)
                       :format-index 0
                       :length length
                       :index-array index-array
                       :access-style access-style))))

;;[TODO] what if location non nil
;;[TODO] this is broken
(defmethod make-gpu-array ((initial-contents list) 
                           &key element-type (index-array nil)
                             (access-style :static-draw) (location nil))
  (with-gl-array (gl-array element-type (length initial-contents) 
                           initial-contents)
    (make-gpu-array gl-array :index-array index-array :access-style access-style
                    :location location)))

(defmethod make-gpu-array ((initial-contents gl-array) &key (index-array nil)
                             (access-style :static-draw) (location nil))
  (if location
      (with-gl-arrays (arrays (append (pull-gl-arrays-from-buffer location)
                                      (list initial-contents)))
        (car (last (make-gpu-arrays arrays :index-array index-array
                                    :access-style access-style
                                    :location location))))
      (let ((buffer (add-buffer-to-pool (gen-buffer))))
        (make-gpuarray :buffer (buffer-data buffer 
                                            initial-contents
                                            (if index-array
                                                :element-array-buffer
                                                :array-buffer)
                                            access-style)
                       :format-index 0
                       :length (array-length initial-contents)
                       :index-array index-array
                       :access-style access-style))))

(defun make-gpu-arrays (gl-arrays &key index-array
                                    (access-style :static-draw)
                                    (location nil))
  "This function creates a list of gpu-arrays residing in a
   single buffer in opengl. It create one gpu-array for each 
   gl-array in the list passed in.

   If these arrays are to be used as an index arrays then set the
   :index-array key to t

   Access style is optional but if you are comfortable with 
   opengl, and know what type of usage pattern thsi array will
   have, you can set this to any of the following:
   (:stream-draw​ :stream-read​ :stream-copy​ :static-draw​ 
    :static-read​ :static-copy​ :dynamic-draw​ :dynamic-read
   ​ :dynamic-copy)

   Finally you can provide an existing buffer if you want to
   use it rather than creating a new buffer. Note that all 
   existing data in the buffer will be destroyed in the process"
  (let ((buffer (or location
                    (add-buffer-to-pool
                     (multi-buffer-data (gen-buffer) 
                                        gl-arrays 
                                        (if index-array
                                            :element-array-buffer
                                            :array-buffer)
                                        access-style)))))
    (loop for gl-array in gl-arrays
       for i from 0 collect 
         (make-gpuarray :buffer buffer
                        :format-index i
                        :length (glarray-length gl-array)
                        :index-array index-array
                        :access-style access-style))))

(defgeneric gl-subseq (array start &optional end)
  (:documentation
   "This function returns a gpu-array or gl-array which contains
   a subset of the array passed into this function.
   Right this will make more sense with a use case:

   Imagine we have one gpu-array with the vertex data for 10
   different monsters inside it and each monster is made of 100
   vertices. The first mosters vertex data will be in the 
   sub-array (gpu-sub-array bigarray 0 1000) and the vertex 
   data for the second monster would be at 
   (gpu-sub-array bigarray 1000 2000)

   This *view* (for lack of a better term) into our array can
   be really damn handy. Prehaps, for example, we want to 
   replace the vertex data of monster 2 with the data in my
   gl-array newmonster. We can simply do the following:
   (gl-push (gpu-sub-array bigarray 1000 2000) newmonster)

   Obviously be aware that any changes you make to the parent
   array affect the child sub-array. This can really bite you
   in the backside if you change how the data in the array is 
   laid out."))

(defmethod gl-subseq ((array gl-array) start &optional end)
  (let* ((length (array-length array))
         (type (array-type array))
         (end (or end length)))
    (if (and (< start end) (< start length) (<= end length))
        (make-gl-array-from-pointer 
         (cffi:inc-pointer (pointer array) (foreign-type-index type start))
         (if (listp type)
             (if (eq :struct (first type))
                 (second type)
                 (error "we dont handle arrays of pointers yet"))
             type)
         (- end start)))
    (error "Invalid subseq start or end for gl-array")))

(defmethod gl-subseq ((array gpuarray) start &optional end)
  (let* ((length (gpuarray-length array))
         (parent-start (gpuarray-start array))
         (new-start (+ parent-start (max 0 start)))
         (end (or end length)))
    (if (and (< start end) (< start length) (<= end length))
        (make-gpuarray 
         :buffer (gpuarray-buffer array)
         :format-index (gpuarray-format-index array)
         :start new-start
         :length (- end start)
         :index-array (gpuarray-index-array array)
         :access-style (gpuarray-access-style array))
        (error "Invalid subseq start or end for gl-array"))))

(defmacro with-gpu-array-as-gl-array ((temp-array-name
                                       gpu-array
                                       access) 
                                      &body body)
  "This macro is really handy if you need to have random access
   to the data on the gpu. It takes a gpu-array and binds it
   to a gl-array which allows you to run any of the gl-array
   commands on it.

   A simple example would be if we wanted to set the 3rd element
   in a gpu array to 5.0 we could do the following:
   (with-gpu-array-as-gl-array (tmp mygpuarray :write-only)
     (setf (aref-gl tmp 2) 5.0))

   The valid values for access are :read-only :write-only & 
   :read-write"
  (let ((glarray-pointer (gensym "POINTER"))
        (buffer-sym (gensym "BUFFER"))
        (target (gensym "target"))
        (ggpu-array (gensym "gpu-array")))
    `(let ((,buffer-sym (gpuarray-buffer ,gpu-array))
           (,target (if (gpuarray-index-array ,gpu-array)
                        :element-array-buffer
                        :array-buffer))
           (,ggpu-array ,gpu-array))
       (force-bind-buffer ,buffer-sym ,target)
       (gl:with-mapped-buffer (,glarray-pointer 
                               ,target
                               ,access)
         (if (pointer-eq ,glarray-pointer (null-pointer))
             (error "with-gpu-array-as-gl-array: buffer mapped to null pointer~%Have you defintely got a opengl context?~%~s"
                    ,glarray-pointer)
             (let ((,temp-array-name 
                    (make-gl-array-from-pointer 
                     (cffi:inc-pointer ,glarray-pointer (gpuarray-offset ,ggpu-array))
                     (let ((array-type (gpuarray-type ,ggpu-array)))
                       (if (listp array-type)
                           (if (eq :struct (first array-type))
                               (second array-type)
                               (error "we dont handle arrays of pointers yet"))
                           array-type))
                     (gpuarray-length ,ggpu-array))))
               ,@body))))))

(defun gpu-array-pull (gpu-array)
  "This function returns the contents of the array as lisp list 
   of the data. 
   Note that you often dont need to use this as the generic
   function gl-pull will call this function if given a gpu-array"
  (with-gpu-array-as-gl-array (tmp gpu-array :read-only)
    (loop for i below (gpuarray-length gpu-array)
       collect (glpull-entry tmp i))))


(defun gpu-array-push (gpu-array gl-array)
  "This function pushes the contents of the specified gl-array
   into the gpu-array.
   Note that you often dont need to use this as the generic
   function gl-push will call this function if given a gpu-array"
  (let* ((buffer (gpuarray-buffer gpu-array))
         (format (nth (gpuarray-format-index gpu-array)
                      (glbuffer-format buffer)))
         (type (first format)))
    (if (and (eq (array-type gl-array) type)
             (<= (array-length gl-array) 
                 (gpuarray-length gpu-array)))
        (setf (gpuarray-buffer gpu-array)
              (buffer-sub-data buffer 
                               gl-array
                               (gpuarray-offset gpu-array)
                               (if (gpuarray-index-array 
                                    gpu-array)
                                   :element-array-buffer
                                   :array-buffer)))
        (error "The gl-array must of the same type as the target gpu-array and not have a length exceeding that of the gpu-array."))
    gpu-array))

;;;--------------------------------------------------------------
;;; VAOS ;;;
;;;------;;;

(let ((vao-cache nil))
  (defun bind-vao (vao)
    (unless (eq vao vao-cache)
      (gl:bind-vertex-array vao)
      (setf vao-cache vao)))
  (defun force-bind-vao (vao)
    (gl:bind-vertex-array vao)
    (setf vao-cache vao)))

(setf (documentation 'bind-vao 'function) 
      "Binds the vao specfied")

(setf (symbol-function 'bind-vertex-array) #'bind-vao)

;; glVertexAttribPointer
;; ---------------------
;; GL_BYTE
;; GL_UNSIGNED_BYTE
;; GL_SHORT
;; GL_UNSIGNED_SHORT
;; GL_INT
;; GL_UNSIGNED_INT 
;; GL_HALF_FLOAT
;; GL_FLOAT

;; GL_DOUBLE
;; GL_FIXED
;; GL_INT_2_10_10_10_REV
;; GL_UNSIGNED_INT_2_10_10_10_REV

;; glVertexAttribLPointer 
;; ----------------------
;; GL_DOUBLE 

;; buffer format is a list whose sublists are of the format
;; type, length, byte-offset-from-start-of-buffer

;; For element-array-buffer the indices can be unsigned bytes, 
;; unsigned shorts, or unsigned ints. 

(defun make-vao-from-formats (formats &key element-buffer)
  "Makes a vao from a list of buffer formats.
   The formats list should be laid out as follows:
   `((buffer1 (attr-format1) (attr-format2))
     (buffer2 (attr-format3) (attr-format4)))
   with each attr-format laid out as follows:
   `(component-type normalized-flag stride pointer)
   if you have the type and offset of the data this can be generated
   by using the function gl-type-format.
   You can also specify an element buffer to be used in the vao"
  (let ((vao (gl:gen-vertex-array))
        (attr-num 0))
    (force-bind-vao vao)
    (loop for format in formats
       :do (let ((buffer (first format)))
             (force-bind-buffer buffer :array-buffer)
             (loop :for (type normalized stride pointer) 
                :in (rest format)
                :do (setf attr-num
                          (+ attr-num
                             (gl-assign-attrib-pointers
                              type pointer stride))))))   
    (when element-buffer
      (force-bind-buffer element-buffer :element-array-buffer))
    (bind-vao 0)
    vao))


;; buffer format is a list whose sublists are of the format
;; type, length, byte-offset-from-start-of-buffer

(defun make-vao-from-gpu-arrays
    (gpu-arrays &optional indicies-array)
  "makes a vao using a list of gpu-arrays as the source data
   (remember that you can also use gpu-sub-array here if you
   need a subsection of a gpu-array).
   You can also specify an indicies-array which will be used as
   the indicies when rendering"
  (let ((element-buffer (when indicies-array
                          (gpuarray-buffer indicies-array)))
        (vao (gl:gen-vertex-array))
        (attr 0))
    (force-bind-vao vao)
    (loop for gpu-array in gpu-arrays
       :do (let* ((buffer (gpuarray-buffer gpu-array))
                  (format (nth (gpuarray-format-index gpu-array)
                               (glbuffer-format buffer))))
             (force-bind-buffer buffer :array-buffer)
             (setf attr (+ attr (gl-assign-attrib-pointers
                                 (let ((type (first format)))
                                   (if (listp type) (second type) type))
                                 attr
                                 (+ (third format)
                                    (cgl:foreign-type-index 
                                     (first format) 
                                     (gpuarray-start gpu-array)))))))) 
    ;; the line above needs start to be taken into account ^^^
    (when element-buffer
      (force-bind-buffer element-buffer :element-array-buffer))
    (bind-vao 0)
    vao))

;;;--------------------------------------------------------------
;;; GPUSTREAMS ;;;
;;;------------;;;

(defstruct gpu-stream 
  "gpu-streams are the structure we use in cepl to pass 
   information to our programs on what to draw and how to draw 
   it.

   It basically adds the only things that arent captured in the
   vao but are needed to draw, namely the range of data to draw
   and the style of drawing.

   If you are using gl-arrays then be sure to use the 
   make-gpu-stream-from-gpu-arrays function as it does all the
   work for you."
  vao
  (start 0 :type unsigned-byte)
  (length 1 :type unsigned-byte)
  (draw-type :triangles :type symbol)
  (index-type nil))

(let ((vao-pool (make-hash-table)))
  (defun add-vao-to-pool (vao key)
    (setf (gethash key vao-pool) vao)
    vao)

  (defun free-all-vaos-in-pool ()
    (mapcar #'(lambda (x) (declare (ignore x)) 
                      (print "freeing a vao")) 
            vao-pool)))

(defun make-gpu-stream-from-gpu-arrays (gpu-arrays &key indicies-array (start 0)
                                                     length
                                                     (draw-type :triangles))
  "This function simplifies making the gpu-stream if you are 
   storing the data in gpu-arrays.

   Remember that you can also use gpu-sub-arrays in here if you
   want to limit the data you are using, for example the 
   following is perfectly legal code:
   (make-gpu-stream-from-gpu-arrays 
     :gpu-arrays `(,(gpu-sub-array monster-pos-data 1000 2000)
                  ,(gpu-sub-array monster-col-data 1000 2000))
     :indicies-array monster-indicies-array
     :length 1000)"
  (let* ((gpu-arrays (if (gpuarray-p gpu-arrays)
                         (list gpu-arrays)
                         gpu-arrays))
         ;; THIS SEEMS WEIRD BUT IF HAVE INDICES ARRAY THEN
         ;; LENGTH MUST BE LENGTH OF INDICES ARRAY NOT NUMBER
         ;; OF TRIANGLES
         (length (or length 
                     (when indicies-array (gpuarray-length
                                           indicies-array))
                     (apply #'min (mapcar #'gpuarray-length 
                                          gpu-arrays)))))
    
    (make-gpu-stream 
     :vao (make-vao-from-gpu-arrays gpu-arrays indicies-array)
     :start start
     :length length
     :draw-type draw-type
     :index-type (when indicies-array 
                   (gpuarray-type indicies-array)))))


;;;--------------------------------------------------------------
;;; PUSH AND PULL ;;;
;;;---------------;;;

(defgeneric gl-pull (gl-object)
  (:documentation "Pulls data from the gl-array or gpu-array back into a native lisp list"))

(defmethod gl-pull ((gl-object gpuarray))
  (gpu-array-pull gl-object))

(defmethod gl-pull ((gl-object gl-array))
  (loop for i below (array-length gl-object)
     collect (glpull-entry gl-object i)))

(defgeneric gl-pull-1 (array &optional destination)
  (:documentation "Pulls data from the gl-array or gpu-array back one layer. This means that a gpu-array gets pulled into a gl-array, and a gl-array to a lisp list"))

(defmethod gl-pull-1 ((array gpuarray) &optional destination)
  (declare (ignore destination))
  (let* ((buffer (gpuarray-buffer array))
         (format (nth (gpuarray-format-index array)
                      (glbuffer-format buffer)))
         (new-array (make-gl-array (let ((array-type (first format)))
                                     (if (listp array-type)
                                         (if (eq :struct (first array-type))
                                             (second array-type)
                                             (error "we dont handle arrays of pointers yet"))
                                         array-type)) 
                                   (second format))))
    (bind-buffer buffer :array-buffer)
    (gl:with-mapped-buffer (b-pointer :array-buffer :read-only)
      (%memcpy (pointer new-array)
               (cffi:inc-pointer b-pointer (third format))
               (gl-array-byte-size new-array)))
    new-array))

(defmethod gl-pull-1 ((array gl-array) &optional destination)
  (declare (ignore destination))
  (loop for i below (array-length array)
     collect (glpull-entry array i)))

(defgeneric gl-push (gl-object data)
  (:documentation ""))

(defmethod gl-push ((gl-object gpuarray) (data gl-array))
  (gpu-array-push gl-object data)
  gl-object)

(defmethod gl-push ((gl-object gpuarray) (data list))
  
  (let ((gl-array (destructuring-allocate 
                   (gpuarray-type gl-object)
                   data)))
    (gpu-array-push gl-object gl-array)
    (free-gl-array gl-array))
  gl-object)

(defmethod gl-push ((gl-object gl-array) (data list))
  (destructuring-populate gl-object data)
  gl-object)

(defgeneric gl-push-1 (gl-object data)
  (:documentation ""))

(defmethod gl-push-1 ((gl-object gl-array) (data list))
  (destructuring-populate gl-object data)
  gl-object)

(defmethod gl-push-1 ((gl-object gpuarray) (data gl-array))
  (gpu-array-push gl-object data)
  gl-object)

;;;--------------------------------------------------------------
;;; HELPERS ;;;
;;;---------;;;

(defun free-managed-resources ()
  (free-all-vaos-in-pool)
  (free-all-buffers-in-pool))

;;;--------------------------------------------------------------
;;; UNIFORMS ;;;
;;;----------;;;

(defun uniform-1i (location value)
  (gl:uniformi location value))

(defun uniform-2i (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-2iv location 1 ptr)))

(defun uniform-3i (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-3iv location 1 ptr)))

(defun uniform-4i (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-4iv location 1 ptr)))

(defun uniform-1f (location value)
  (gl:uniformf location value))

(defun uniform-2f (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-2fv location 1 ptr)))

(defun uniform-3f (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-3fv location 1 ptr)))

(defun uniform-4f (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-4fv location 1 ptr)))

(defun uniform-matrix-2ft (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-matrix-2fv location 1 nil ptr)))

(defun uniform-matrix-3ft (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-matrix-3fv location 1 nil ptr)))

(defun uniform-matrix-4ft (location value)
  (cffi-sys:with-pointer-to-vector-data (ptr value)
    (%gl:uniform-matrix-4fv location 1 nil ptr)))

(defun uniform-matrix-2fvt (location count value)
  (%gl:uniform-matrix-2fv location count nil value))

(defun uniform-matrix-3fvt (location count value)
  (%gl:uniform-matrix-3fv location count nil value))

(defun uniform-matrix-4fvt (location count value)
  (%gl:uniform-matrix-4fv location count nil value))

;; [TODO] HANDLE DOUBLES
(defun get-foreign-uniform-function (type)
  (case type
    ((:int :int-arb :bool :bool-arb :sampler_1d :sampler_1d_shadow 
           :sampler_2d :sampler_3d :sampler_cube 
           :sampler_2d_shadow) #'%gl:uniform-1iv)
    ((:float :float-arb) #'%gl:uniform-1fv)
    ((:int-vec2 :int-vec2-arb :bool-vec2 :bool-vec2-arb) #'%gl:uniform-2iv)
    ((:int-vec3 :int-vec3-arb :bool-vec3 :bool-vec3-arb) #'%gl:uniform-3iv)
    ((:int-vec4 :int-vec4-arb :bool-vec4 :bool-vec4-arb) #'%gl:uniform-4iv)
    ((:float-vec2 :float-vec2-arb) #'%gl:uniform-2fv)
    ((:float-vec3 :float-vec3-arb) #'%gl:uniform-3fv)
    ((:float-vec4 :float-vec4-arb) #'%gl:uniform-4fv)
    ((:float-mat2 :float-mat2-arb) #'uniform-matrix-2fvt)
    ((:float-mat3 :float-mat3-arb) #'uniform-matrix-3fvt)
    ((:float-mat4 :float-mat4-arb) #'uniform-matrix-4fvt)
    (t (error "Sorry cepl doesnt handle that type yet"))))

(defun get-uniform-function (type)
  (case type
    ((:int :int-arb :bool :bool-arb :sampler_1d :sampler_1d_shadow 
           :sampler_2d :sampler_3d :sampler_cube 
           :sampler_2d_shadow) #'uniform-1i)
    ((:float :float-arb) #'uniform-1f)
    ((:int-vec2 :int-vec2-arb :bool-vec2 :bool-vec2-arb) #'uniform-2i)
    ((:int-vec3 :int-vec3-arb :bool-vec3 :bool-vec3-arb) #'uniform-3i)
    ((:int-vec4 :int-vec4-arb :bool-vec4 :bool-vec4-arb) #'uniform-4i)
    ((:float-vec2 :float-vec2-arb) #'uniform-2f)
    ((:float-vec3 :float-vec3-arb) #'uniform-3f)
    ((:float-vec4 :float-vec4-arb) #'uniform-4f)
    ((:float-mat2 :float-mat2-arb) #'uniform-matrix-2ft)
    ((:float-mat3 :float-mat3-arb) #'uniform-matrix-3ft)
    ((:float-mat4 :float-mat4-arb) #'uniform-matrix-4ft)
    (t (error "Sorry cepl doesnt handle that type yet"))))

;;;--------------------------------------------------------------
;;; SHADER & PROGRAMS ;;;
;;;-------------------;;;

(let ((programs (make-hash-table)))
  (defun program-manager (name)
    (let ((prog-id (gethash name programs)))
      (if prog-id prog-id
          (setf (gethash name programs) (gl:create-program)))))
  (defun program-manager-delete (name)
    (declare (ignore name))
    (print "delete not yet implemented")))

(defun valid-shader-typep (shader)
  (find (first shader) '(:vertex :fragment :geometry)))

;; [TODO] We need to make this fast, this 'if not prog' won't do
(defmacro defpipeline (name (&rest args) &body shaders)
  (if (> (count :post-compile shaders :key #'first) 1)
      (error "Cannot not have more than one :post-compile section")
      (let ((post (rest (find :post-compile shaders :key #'first)))
            (shaders (remove :post-compile shaders :key #'first)))
        (if (every #'valid-shader-typep shaders)
            (let* ((uniform-names (mapcar #'first (varjo:extract-uniforms args))))
              `(let ((program nil))
                 (defun ,name (stream ,@(when uniform-names `(&key ,@uniform-names)))
                   (when (not program) 
                     (setf program (make-program ,name ,args ,shaders))
                     ,@post)
                   (funcall program stream ,@(loop for name in uniform-names 
                                                :append `(,(utils:kwd name)
                                                           ,name))))))
            (error "Some shaders have invalid types ~a" (mapcar #'first shaders))))))

(defmacro defpipeline? (name (&rest args) &body shaders)
  (declare (ignore name))
  (let ((shaders (remove :post-compile shaders :key #'first)))
    (if (every #'valid-shader-typep shaders)
        `(let* ((shaders (varjo:rolling-translate ',args ',shaders)))
           (format t "~&~{~{~(#~a~)~%~a~}~^-----------~^~%~^~%~}~&" shaders)
           nil)
        (error "Some shaders have invalid types ~a" (mapcar #'first shaders)))))

(defmacro glambda ((&rest args) &body shaders)
  `(make-program nil ,args ,shaders))

;; [TODO] Make glambda handle strings
(defmacro make-program (name args shaders)  

  (let* ((uniforms (varjo:extract-uniforms args))
         (uniform-names (mapcar #'first uniforms)))
    
    `(let* ((shaders (loop for (type code) in (varjo:rolling-translate 
                                               ',args ',shaders)
                        :collect (make-shader type code)))
            (program-id (link-shaders 
                         shaders
                         ,(if name
                              `(program-manager ',name)
                              `(gl:create-program))))

            
            (assigners (create-uniform-assigners 
                        program-id ',uniforms 
                        ,(utils:kwd (package-name (symbol-package name)))))
            ,@(loop :for name :in uniform-names :for i :from 0
                 :collect `(,(utils:symb name '-assigner)
                             (nth ,i assigners))))
       (declare (ignorable assigners))
       (mapcar #'%gl:delete-shader shaders)
       (unbind-buffer)
       (force-bind-vao 0)
       (force-use-program 0)
       (lambda (stream ,@(when uniforms `(&key ,@uniform-names)))
         (use-program program-id)
         ,@(loop :for uniform-name :in uniform-names
              :collect `(when ,uniform-name
                          (dolist (fun ,(utils:symb uniform-name
                                                    '-assigner))
                            (funcall fun ,uniform-name))))
         (when stream (no-bind-draw-one stream))))))

;; make this return list of funcs or nil for each uni-var
(defun create-uniform-assigners (program-id uniform-vars package)
  (let* ((uniform-details (program-uniforms program-id))
         (active-uniform-details (process-uniform-details uniform-details
                                                          uniform-vars
                                                          package)))
    (loop for a-uniform in active-uniform-details
       :collect
         (when a-uniform
           (let ((location (gl:get-uniform-location program-id 
                                                    (second a-uniform))))
             (if (< location 0)
                 (error "uniform ~a not found, this is a bug in cepl"
                        (second a-uniform))
                 (loop for part in (subseq a-uniform 2)
                    :collect 
                      (destructuring-bind (offset type length) part
                        (let ((uni-fun (get-foreign-uniform-function type))
                              (uni-fun2 (get-uniform-function type)))
                          (if (or (> length 1) (varjo:type-struct-p type))
                              (lambda (pointer)
                                (funcall uni-fun location length
                                         (cffi-sys:inc-pointer pointer offset)))
                              (lambda (value) (funcall uni-fun2 location value))))))))))))

;; [TODO] Got to be a quicker and tidier way
(defun process-uniform-details (uniform-details uniform-vars package)
  ;; returns '(byte-offset principle-type length)
  (let ((result nil)
        (paths (loop for det in uniform-details
                  collect (parse-uniform-path det package))))
    (loop for detail in uniform-details
       for path in paths
       :do (setf result 
                 (acons (caar path) 
                        (cons (first detail)
                              (cons (list (get-path-offset path uniform-vars)
                                          (second detail)
                                          (third detail))
                                    (rest (rest 
                                           (assoc (caar path)
                                                  result)))))
                        result)))
    (loop for var in uniform-vars
       :collect (assoc (first var) result))))

;; [TODO] If we load shaders from files the names will clash
(defun parse-uniform-path (uniform-detail package)
  (labels ((s-dot (x) (split-sequence:split-sequence #\. x))
           (s-square (x) (split-sequence:split-sequence #\[ x)))
    (loop for path in (s-dot (first uniform-detail))
       :collect (let ((part (s-square (remove #\] path))))
                  (list (symbol-munger:camel-case->lisp-symbol (first part) 
                                                               package)
                        (if (second part)
                            (parse-integer (second part))
                            0))))))

(defun get-slot-type (parent-type slot-name)
  (second (assoc slot-name (varjo:struct-definition parent-type))))

(defun get-path-offset (path uniform-vars)
  (labels ((path-offset (type path &optional (sum 0))
             (if path
                 (let* ((path-part (first path))
                        (slot-name (first path-part))
                        (child-type (varjo:type-principle
                                     (get-slot-type type
                                                    slot-name))))
                   (path-offset 
                    child-type
                    (rest path)
                    (+ sum
                       (+ (cffi:foreign-slot-offset type slot-name) 
                          (* (cffi:foreign-type-size child-type)
                             (second path-part))))))
                 sum)))
    (let* ((first-part (first path))
           (type (second (assoc (symbol-name (first first-part)) uniform-vars
                                :key #'symbol-name :test #'equal)))
           (index (second first-part)))
      (if type
          (+ (* (cffi:foreign-type-size type) index)
             (path-offset type (rest path)))
          (error "Could not find the uniform variable named '~a'" 
                 (first first-part))))))

(defun program-attrib-count (program)
  "Returns the number of attributes used by the shader"
  (gl:get-program program :active-attributes))

(defun program-attributes (program)
  "Returns a list of details of the attributes used by
   the program. Each element in the list is a list in the
   format: (attribute-name attribute-type attribute-size)"
  (loop for i from 0 below (program-attrib-count program)
     collect (multiple-value-bind (size type name)
                 (gl:get-active-attrib program i)
               (list name type size))))

(defun program-uniform-count (program)
  "Returns the number of uniforms used by the shader"
  (gl:get-program program :active-uniforms))

(defun program-uniforms (program-id)
  "Returns a list of details of the uniforms used by
   the program. Each element in the list is a list in the
   format: (uniform-name uniform-type uniform-size)"
  (loop for i from 0 below (program-uniform-count program-id)
     collect (multiple-value-bind (size type name)
                 (gl:get-active-uniform program-id i)
               (list name type size))))


(let ((program-cache nil))
  (defun use-program (program-id)
    (unless (eq program-id program-cache)
      (gl:use-program program-id)
      (setf program-cache program-id)))
  (defun force-use-program (program-id)
    (gl:use-program program-id)
    (setf program-cache program-id)))
(setf (documentation 'use-program 'function) 
      "Installs a program object as part of current rendering state")

(defun shader-type-from-path (path)
  "This uses the extension to return the type of the shader.
   Currently it only recognises .vert or .frag files"
  (let* ((plen (length path))
         (exten (subseq path (- plen 5) plen)))
    (cond ((equal exten ".vert") :vertex-shader)
          ((equal exten ".frag") :fragment-shader)
          (t (error "Could not extract shader type from shader file extension (must be .vert or .frag)")))))

(defun make-shader 
    (shader-type source-string &optional (shader-id (gl:create-shader 
                                                     shader-type)))
  "This makes a new opengl shader object by compiling the text
   in the specified file and, unless specified, establishing the
   shader type from the file extension"
  (gl:shader-source shader-id source-string)
  (gl:compile-shader shader-id)
  ;;check for compile errors
  (when (not (gl:get-shader shader-id :compile-status))
    (error "Error compiling ~(~a~): ~%~a~%~%~a" 
           shader-type
           (gl:get-shader-info-log shader-id)
           source-string))
  shader-id)

(defun load-shader (file-path 
                    &optional (shader-type 
                               (shader-type-from-path file-path)))
  (restart-case
      (make-shader (utils:file-to-string file-path) shader-type)
    (reload-recompile-shader () (load-shader file-path
                                             shader-type))))

(defun load-shaders (&rest shader-paths)
  (mapcar #'load-shader shader-paths))

(defun link-shaders (shaders &optional program_id)
  "Links all the shaders provided and returns an opengl program
   object. Will recompile an existing program if ID is provided"
  (let ((program (or program_id (gl:create-program))))
    (loop for shader in shaders
       do (gl:attach-shader program shader))
    (gl:link-program program)
    ;;check for linking errors
    (if (not (gl:get-program program :link-status))
        (error (format nil "Error Linking Program~%~a" 
                       (gl:get-program-info-log program))))
    (loop for shader in shaders
       do (gl:detach-shader program shader))
    program))

;; [TODO] Need to sort gpustream indicies thing
(defun no-bind-draw-one (stream)
  "This draws the single stream provided using the currently 
   bound program. Please note: It Does Not bind the program so
   this function should only be used from another function which
   is handling the binding."
  (let ((index-type (gpu-stream-index-type stream)))
    (bind-vao (gpu-stream-vao stream))
    (if index-type
        (%gl:draw-elements (gpu-stream-draw-type stream)
                           (gpu-stream-length stream)
                           (gl::cffi-type-to-gl index-type)
                           (make-pointer 0))
        (%gl:draw-arrays (gpu-stream-draw-type stream)
                         (gpu-stream-start stream)
                         (gpu-stream-length stream)))))

(defun cls (&optional (flags '(:color-buffer-bit)))
  (apply #'cgl:clear flags)
  (sdl:update-display))

;; [TODO] There can be only one!!
(defun lispify-name (name)
  "take a string and changes it to uppercase and replaces
   all underscores _ with minus symbols -"
  (string-upcase (substitute #\- #\_ name)))


(defun gpu! (type &rest values)
  (if (and (not values) (typep type 'cgl::gl-array))
      (make-gpu-array type)
      (make-gpu-array values :element-type type)))

(defun gl! (type &rest values)
  (make-gl-array type (length values) values))